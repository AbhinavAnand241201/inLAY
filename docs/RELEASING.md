# Releasing Inlay

Cutting a release is now mostly one command. A tag push triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which
computes the source-tarball SHA-256, publishes a GitHub Release, and bumps the
Homebrew formula in the tap repo automatically.

## One-time setup

1. **Create the tap** (public repo `AbhinavAnand241201/homebrew-tap`, empty), then:
   ```bash
   git clone https://github.com/AbhinavAnand241201/homebrew-tap.git
   cd homebrew-tap && mkdir -p Formula
   curl -fsSL https://raw.githubusercontent.com/AbhinavAnand241201/inLAY/main/cli/Formula/inlay.rb -o Formula/inlay.rb
   git add Formula/inlay.rb && git commit -m "Add inlay formula" && git push
   ```
2. **Add the `TAP_TOKEN` secret** so the release workflow can push to the tap:
   - Create a token at GitHub → Settings → Developer settings → **Personal access
     tokens**. Fine-grained: only the `homebrew-tap` repo, **Contents: Read/Write**.
     (Or a classic token with `repo` scope.)
   - Add it in the **inLAY** repo → Settings → Secrets and variables → Actions →
     New repository secret → name `TAP_TOKEN`.
   - If you skip this, the release still publishes; only the tap bump is skipped.

## Cutting a release

1. Bump the CLI version in
   [`cli/Sources/inlay/Inlay.swift`](../cli/Sources/inlay/Inlay.swift)
   (`version: "X.Y.Z"`).
2. Sync the registry into the CLI bundle + website:
   ```bash
   ./scripts/sync-registry.sh
   ```
3. Commit, then tag and push:
   ```bash
   git commit -am "Release vX.Y.Z"
   git push origin main
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```

That's it. The Release workflow then:
- downloads the `vX.Y.Z` source tarball and computes its SHA-256,
- creates the GitHub Release (auto-generated notes),
- updates `url` + `sha256` in `homebrew-tap/Formula/inlay.rb` and pushes it.

Within a minute, `brew upgrade inlay` (or a fresh `brew install
AbhinavAnand241201/tap/inlay`) gives users the new version. The website
redeploys on its own from the `website/**` change via the Pages workflow.

> The CLI's remote registry fallback is pinned to `main`, so it never needs a
> per-release edit. The bundled registry (the primary source) always matches the
> released binary because step 2 compiles it in.
