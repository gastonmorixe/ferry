---
name: ship
description: Use when finishing a feature or fix and ready to release — runs lint, tests, docs check, personal data audit, version bump, changelog, commit, tag, merge to main, and push to origin.
---

# /ship — Pre-Release Checklist and Push

## Overview

Cascade checklist that validates, versions, commits, and pushes a Ferry release. Runs from a feature branch, merges to main, tags, and pushes.

## When to Use

- After completing a feature, fix, or improvement
- When the user says "ship it", "push", "release", or invokes `/ship`
- Before any code reaches the public GitHub repo

## Workflow

```
feature-branch → lint → test → docs → audit → version → changelog → commit → merge main → tag → push
```

## Steps

### 1. Branch Check

Confirm we're on a feature branch (not main). If on main, warn and ask to proceed.

```bash
current=$(git branch --show-current)
if [ "$current" = "main" ]; then
  # warn: "You're on main. Create a feature branch or proceed directly?"
fi
git status --short  # must be clean or have only expected changes
```

### 2. Lint

```bash
make lint
```

Must exit 0. Also run:
```bash
bash -n ferry
```

### 3. Tests

Run all test suites and confirm pass counts:

```bash
bats test/unit/
bats test/integration/
bats test/generators/all_generators.bats
```

All must pass. Report total count. If Docker tests are included (runtime HTTP 200), they may take a few minutes — run them.

### 4. Docs Check

Verify version consistency:
- `FERRY_VERSION` in `ferry` (line 9) matches the intended release version
- `CHANGELOG.md` has an entry for this version at the top
- No stale version references in README or docs

```bash
grep 'FERRY_VERSION=' ferry | head -1
head -6 CHANGELOG.md
```

### 5. Personal Data Audit

**CRITICAL for this public repo.** Scan staged/changed files for personal data:

```bash
git diff --cached --name-only | xargs grep -il 'gastonmorixe\.com\|kitekite\|bedhero\|gooseup\|ledsport\|multifiesta\|shieldsdev\|rails-fields\|5ac59747' 2>/dev/null
```

Also check for:
- Real Cloudflare tunnel IDs, account IDs, zone IDs
- API tokens or credentials
- Real domain names (except in the GitHub repo URL `gastonmorixe/ferry` which is intentional)
- Private IPs or hostnames

If anything found, **STOP** and ask the user before proceeding.

### 6. Version Bump

If not already bumped, determine the next version:
- **Patch** (0.6.x): bug fixes, small improvements, branding changes
- **Minor** (0.x.0): new features, new generators, new commands
- **Major** (x.0.0): breaking changes

Update `FERRY_VERSION` in `ferry` script. Always run `date -Iseconds` for timestamps.

### 7. Changelog

Add entry at top of `CHANGELOG.md` with:
- Version and date
- Sections: Added / Changed / Fixed (as applicable)
- Concise but specific descriptions of what changed

### 8. Commit

Stage specific files (never `git add -A`):
```bash
git add ferry CHANGELOG.md [other changed files...]
```

Commit with a detailed message using heredoc:
```bash
git commit -m "$(cat <<'EOF'
Ferry v{VERSION} — {one-line summary}

{detailed description of changes}
EOF
)"
```

### 9. Merge to Main

```bash
git checkout main
git merge --no-ff {feature-branch} -m "Merge {feature-branch}: {summary}"
```

If conflicts, stop and resolve with user.

### 10. Tag

```bash
git tag v{VERSION}
```

### 11. Push

```bash
git push origin main
git push origin v{VERSION}
```

### 12. Cleanup (optional)

Ask user if they want to delete the feature branch:
```bash
git branch -d {feature-branch}
```

## Checklist Summary (for quick reference)

| Step | Command | Must pass |
|------|---------|-----------|
| Branch | `git branch --show-current` | Not main (or acknowledged) |
| Lint | `make lint` | exit 0 |
| Syntax | `bash -n ferry` | exit 0 |
| Unit tests | `bats test/unit/` | all pass |
| Integration | `bats test/integration/` | all pass |
| Generator | `bats test/generators/` | all pass |
| Version | `grep FERRY_VERSION ferry` | matches release |
| Changelog | `head CHANGELOG.md` | has version entry |
| Data audit | grep for personal data | nothing found |
| Commit | `git commit` | clean message |
| Merge | `git merge --no-ff` | no conflicts |
| Tag | `git tag v{VERSION}` | created |
| Push | `git push origin main` | success |
| Push tag | `git push origin v{VERSION}` | success |

## Red Flags — STOP

- Personal data in staged files
- Tests failing
- Lint errors
- Version mismatch between ferry script and changelog
- Uncommitted changes on main before merge
- Force push needed (never force push to main)
