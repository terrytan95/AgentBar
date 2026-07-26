# Release process

How to cut an AgentBar GitHub + Homebrew release.

## Policy

- **Do not run tests** unless the user explicitly asks.
- Ship from current `main` tip after version bump.
- Prefer speed: package → publish → update brew.

## Preconditions

- Clean `main`, up to date with `origin/main`.
- At least one unreleased commit since the latest `v*` tag (or user asks for a rebuild/republish).
- Local signing identity available (`AgentBar Local Code Signing` or Developer ID). Packaging fails without a stable identity unless `AGENTBAR_ALLOW_ADHOC_PACKAGE=1`.

## Versioning

1. Read current values from `script/build_and_run.sh`:
   - `APP_VERSION` (e.g. `2.3.12`)
   - `APP_BUILD` (e.g. `222`)
2. Bump patch version by default: `2.3.12` → `2.3.13`.
3. Increment build by 1: `222` → `223`.
4. Tag / release name: `v{APP_VERSION}` (e.g. `v2.3.13`).

Only use minor/major bumps when the user asks.

## Steps

### 1. Branch + version bump

```bash
git checkout main && git pull origin main
git checkout -b terry-release-vX.Y.Z
# edit script/build_and_run.sh: APP_VERSION + APP_BUILD
```

Commit message shape:

```text
chore(release): bump to vX.Y.Z

Bumps AgentBar to vX.Y.Z (build N) for <one-line reason>.
```

### 2. Package (no tests)

```bash
./script/build_and_run.sh --package
```

Confirm:

- `CFBundleShortVersionString` == `X.Y.Z`
- `CFBundleVersion` == build number
- codesign identity is stable (not ad-hoc `-`)

### 3. Zip

Clean zip **without** `__MACOSX` resource forks:

```bash
rm -f dist/AgentBar-vX.Y.Z.zip
(cd dist && ditto -c -k --keepParent AgentBar.app AgentBar-vX.Y.Z.zip)
shasum -a 256 dist/AgentBar-vX.Y.Z.zip
```

Optional local notes file (gitignored under `dist/`):

```bash
cat > dist/release-notes-vX.Y.Z.md <<'EOF'
- Bullet from unreleased commits since previous tag.
EOF
```

### 4. Land the bump on main

`main` requires a pull request (ruleset). Open PR, then admin-merge:

```bash
git push -u origin HEAD
gh pr create --title "chore(release): bump to vX.Y.Z" --body "..."
gh pr merge --merge --admin --delete-branch
git checkout main && git pull origin main
```

### 5. GitHub Release

```bash
gh release create vX.Y.Z \
  dist/AgentBar-vX.Y.Z.zip \
  --title "vX.Y.Z" \
  --target main \
  --notes "$(cat dist/release-notes-vX.Y.Z.md)"
```

Release notes: short bullets from commits since the previous tag. Match prior tone (imperative, product-facing).

Verify asset digest matches local SHA256.

### 6. Homebrew tap

Repo: `terrytan95/homebrew-tap`  
Cask: `Casks/agentbar.rb`

Update `version` and `sha256` only (keep the rest of the cask as-is). SHA must match the uploaded release ZIP.

```bash
# after release asset is public
gh pr create --repo terrytan95/homebrew-tap ...
gh pr merge N --repo terrytan95/homebrew-tap --merge --admin --delete-branch
```

PR title: `feat(agentbar): update to vX.Y.Z`

## Checklist

- [ ] Version + build bumped in `script/build_and_run.sh`
- [ ] Packaged with stable codesign
- [ ] Zip has no `__MACOSX` entries
- [ ] Version bump PR merged to `main`
- [ ] GitHub release `vX.Y.Z` published with `AgentBar-vX.Y.Z.zip`
- [ ] Homebrew cask version + sha256 updated and merged

## Do not

- Run `swift test` / full verification suites unless asked
- Use `ditto ... --sequesterRsrc` (creates `__MACOSX` noise)
- Ad-hoc sign release packages
- Change Homebrew cask fields other than `version` / `sha256` without a reason
