# Inlay

[![CI](https://github.com/AbhinavAnand241201/inLAY/actions/workflows/ci.yml/badge.svg)](https://github.com/AbhinavAnand241201/inLAY/actions/workflows/ci.yml)
[![Deploy website](https://github.com/AbhinavAnand241201/inLAY/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/AbhinavAnand241201/inLAY/actions/workflows/deploy-pages.yml)

> Copy-paste UIKit components for iOS — **shadcn/ui for iOS.**
> Search a component, run one command, and the source lands in your Xcode
> project ready to customize. You own the code; Inlay isn't a dependency you import.

**Gallery:** https://abhinavanand241201.github.io/inLAY/ · 15 components and counting.

```bash
inlay add floating-toolbar
```

See [`ROADMAP.md`](ROADMAP.md) for the product vision, [`DETAILS.md`](DETAILS.md)
for the architecture decisions, and [`CLAUDE.md`](CLAUDE.md) for the build contract.

## Repo layout

```
registry/        Source of truth — real, compiling Swift + a manifest per component.
  spring-animator/      Inlay+SpringAnimator.swift  (shared primitive)
  floating-toolbar/     FloatingToolbar.swift       (component)
scripts/         build-registry.swift → registry.json ; sync-registry.sh
registry.json    Generated artifact the CLI + website consume.
cli/             The `inlay` CLI (Swift + swift-argument-parser).
demo/InlayDemo/  Xcode app that compile-tests the registry components.
website/         Next.js gallery (brutalist B&W) that reads data/registry.json.
docs/            FLOATING_TOOLBAR_TEST.md — the on-device usability pass.
```

## The pipeline

```
registry/*.swift ──(scripts/build-registry.swift)──► registry.json
                                                        │
                            website (reads it) ◄────────┤
                            cli (bundles it)  ◄─────────┘
```

The source of truth is **compilable Swift**, so components never rot. Everything
downstream is generated.

## Common tasks

```bash
# Regenerate registry.json and sync it into the CLI + website
./scripts/sync-registry.sh

# Validate the registry without writing (existence, deps resolve, no cycles)
swift scripts/build-registry.swift --check

# Build & try the CLI
cd cli && swift build && swift run inlay list

# Build the demo app for the simulator
cd demo/InlayDemo && xcodegen generate && \
  xcodebuild -project InlayDemo.xcodeproj -scheme InlayDemo \
    -destination 'generic/platform=iOS Simulator' build

# Run the website (Next.js)
cd website && npm install && npm run dev     # → http://localhost:3000
```

## CI / CD

Two GitHub Actions workflows in [`.github/workflows/`](.github/workflows/):

- **`ci.yml`** (every PR + push) — validates the registry (deps resolve, acyclic,
  `registry.json` in sync), type-checks every component against the iOS 16 SDK,
  builds + smoke-tests the CLI, builds the demo app for the Simulator, and builds
  the website.
- **`deploy-pages.yml`** (push to `main` touching `website/`) — static-exports the
  Next.js site with `BASE_PATH=/inLAY` and deploys it to GitHub Pages.

**One-time setup:** in the repo, **Settings → Pages → Build and deployment →
Source: GitHub Actions**. After that, every push to `main` republishes the
gallery at the URL above.

## Adding a component

1. Create `registry/<name>/<Name>.swift` following the conventions in
   [`CLAUDE.md`](CLAUDE.md) (use `FloatingToolbar.swift` as the reference shape).
2. Add `registry/<name>/manifest.json` (see the schema in `CLAUDE.md`).
3. Run `./scripts/sync-registry.sh`.
4. Add the file to `demo/InlayDemo/project.yml` and build to verify.
# inLAY
