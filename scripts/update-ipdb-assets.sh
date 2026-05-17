#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/generators/_shared/assets/ipdb"
FORCE="${1:-}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$ASSET_DIR"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

read_key() {
    # $1 = jq-style path like .sapics.commit, $2 = file
    local path="$1" file="$2"
    [[ -f "$file" ]] || { echo ""; return 0; }
    python3 - "$file" "$path" <<'PY' 2>/dev/null || echo ""
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("")
    sys.exit(0)
keys = sys.argv[2].lstrip(".").split(".")
cur = data
for k in keys:
    if not isinstance(cur, dict) or k not in cur:
        print("")
        sys.exit(0)
    cur = cur[k]
print(cur if isinstance(cur, str) else "")
PY
}

resolve_main_sha() {
    git ls-remote "$1" refs/heads/main | awk '{print $1}'
}

sapics_current="$(read_key .sapics.commit "$ASSET_DIR/ipdb-source.json")"
x4bnet_current="$(read_key .x4bnet.commit "$ASSET_DIR/ipdb-source.json")"

sapics_latest="$(resolve_main_sha https://github.com/sapics/ip-location-db.git)"
x4bnet_latest="$(resolve_main_sha https://github.com/X4BNet/lists_vpn.git)"

if [[ -z "$sapics_latest" || -z "$x4bnet_latest" ]]; then
    echo "failed to resolve upstream SHAs (sapics='$sapics_latest', x4bnet='$x4bnet_latest')" >&2
    exit 1
fi

up_to_date=1
[[ "$sapics_current" != "$sapics_latest" ]] && up_to_date=0
[[ "$x4bnet_current" != "$x4bnet_latest" ]] && up_to_date=0
# Tor + PeeringDB don't have stable SHAs; always refresh on full runs but skip if other sources matched.
if [[ "$FORCE" != "--force" && $up_to_date -eq 1 ]]; then
    echo "IPDB assets already up to date (sapics=$sapics_latest, x4bnet=$x4bnet_latest)"
    exit 0
fi

echo "Downloading sapics country + asn CSVs ($sapics_latest)…"
curl -L --fail --silent --show-error \
    "https://raw.githubusercontent.com/sapics/ip-location-db/main/geo-whois-asn-country/geo-whois-asn-country-ipv4-num.csv" \
    -o "$TMP_DIR/geo-whois-asn-country-ipv4-num.csv"
curl -L --fail --silent --show-error \
    "https://raw.githubusercontent.com/sapics/ip-location-db/main/iptoasn-asn/iptoasn-asn-ipv4-num.csv" \
    -o "$TMP_DIR/iptoasn-asn-ipv4-num.csv"

echo "Downloading X4BNet VPN + datacenter CIDR lists ($x4bnet_latest)…"
curl -L --fail --silent --show-error \
    "https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/vpn/ipv4.txt" \
    -o "$TMP_DIR/x4bnet-vpn-ipv4.txt"
curl -L --fail --silent --show-error \
    "https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/datacenter/ipv4.txt" \
    -o "$TMP_DIR/x4bnet-datacenter-ipv4.txt"

echo "Downloading Tor exit list…"
curl -L --fail --silent --show-error \
    "https://check.torproject.org/torbulkexitlist" \
    -o "$TMP_DIR/tor-exits.txt"

echo "Downloading PeeringDB net dump (ASN→info_type)…"
curl -L --fail --silent --show-error \
    -H "User-Agent: ferry-ipdb-updater" \
    "https://www.peeringdb.com/api/net" \
    -o "$TMP_DIR/peeringdb-net-full.json"
python3 - "$TMP_DIR/peeringdb-net-full.json" "$TMP_DIR/peeringdb-asn-types.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
out = {}
for row in src.get("data", []):
    asn = row.get("asn")
    info_type = (row.get("info_type") or "").strip()
    if asn and info_type:
        out[str(asn)] = info_type
json.dump(out, open(sys.argv[2], "w"), separators=(",", ":"))
PY
rm -f "$TMP_DIR/peeringdb-net-full.json"

python3 - "$TMP_DIR/ipdb-source.json" \
    "$sapics_latest" "$x4bnet_latest" "$NOW" <<'PY'
import json, sys
path, sapics, x4bnet, now = sys.argv[1:]
manifest = {
    "sapics": {
        "repo": "https://github.com/sapics/ip-location-db",
        "commit": sapics,
        "fetchedAt": now,
        "files": {
            "country": "geo-whois-asn-country-ipv4-num.csv",
            "asn": "iptoasn-asn-ipv4-num.csv",
        },
    },
    "x4bnet": {
        "repo": "https://github.com/X4BNet/lists_vpn",
        "commit": x4bnet,
        "fetchedAt": now,
        "files": {
            "vpn": "x4bnet-vpn-ipv4.txt",
            "datacenter": "x4bnet-datacenter-ipv4.txt",
        },
    },
    "tor": {
        "url": "https://check.torproject.org/torbulkexitlist",
        "fetchedAt": now,
        "file": "tor-exits.txt",
    },
    "peeringdb": {
        "url": "https://www.peeringdb.com/api/net",
        "fetchedAt": now,
        "file": "peeringdb-asn-types.json",
    },
}
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY

# Atomic move-in
for f in geo-whois-asn-country-ipv4-num.csv iptoasn-asn-ipv4-num.csv \
         x4bnet-vpn-ipv4.txt x4bnet-datacenter-ipv4.txt \
         tor-exits.txt peeringdb-asn-types.json ipdb-source.json; do
    mv "$TMP_DIR/$f" "$ASSET_DIR/$f"
done

echo "Updated vendored IPDB assets:"
echo "  sapics:   ${sapics_current:-none} -> $sapics_latest"
echo "  x4bnet:   ${x4bnet_current:-none} -> $x4bnet_latest"
echo "  tor:      refreshed at $NOW ($(wc -l < "$ASSET_DIR/tor-exits.txt") exit IPs)"
echo "  peeringdb: refreshed at $NOW ($(python3 -c "import json; print(len(json.load(open('$ASSET_DIR/peeringdb-asn-types.json'))))") ASN classifications)"
