# Ferry — Project Instructions

## Git Workflow

- Local `main` is the public branch, pushed to `origin/main`
- Feature work happens on feature branches, merged to main via `/ship`
- `old-main` and `open-source-prep` are legacy branches — do NOT push these
- **NEVER** commit personal data (real domains, tunnel IDs, account IDs) to main
- Push with `git push origin main` (not `oss:main` — the oss branch was renamed)

## Testing

- Run all tests: `make test` or `make check` (lint + tests)
- Unit: `bats test/unit/`
- Integration: `bats test/integration/`
- Generators: `bats test/generators/all_generators.bats`
- Lint: `make lint`
- Syntax check: `bash -n ferry`

## Version

- Version lives in `ferry` script line 9: `FERRY_VERSION="x.y.z"`
- Changelog: `CHANGELOG.md`
- Always bump version BEFORE doing work if other agents may have made changes

## Skills

### /ship — Pre-release checklist and push

Invoke with `/ship` when ready to release. Runs this cascade:

1. **Branch check** — confirm on feature branch (not main)
2. **Lint** — `make lint` + `bash -n ferry`
3. **Tests** — all unit, integration, and generator tests (including Docker runtime HTTP 200)
4. **Docs check** — version in ferry matches changelog, no stale refs
5. **Personal data audit** — scan for real domains, tunnel IDs, credentials in staged files
6. **Version bump** — if not already done, bump FERRY_VERSION (patch/minor/major)
7. **Changelog** — add entry to CHANGELOG.md with date from `date -Iseconds`
8. **Commit** — stage specific files, commit with detailed heredoc message
9. **Merge to main** — `git checkout main && git merge --no-ff {branch}`
10. **Tag** — `git tag v{VERSION}`
11. **Push** — `git push origin main && git push origin v{VERSION}`
12. **Cleanup** — optionally delete feature branch

Full skill spec: `.claude/skills/ship/SKILL.md`

**Red flags that STOP the process:**
- Personal data in staged files
- Any test failing
- Lint errors
- Version mismatch between ferry and changelog
- Merge conflicts
