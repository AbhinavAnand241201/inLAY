# inlay CLI

The `inlay` command writes copy-paste UIKit components into your Xcode project,
resolving each component's registry dependencies and installing shared primitives
only once.

## Build & run

```bash
swift build
swift run inlay list
# or install the release binary somewhere on PATH:
swift build -c release
cp .build/release/inlay /usr/local/bin/inlay
```

The registry is bundled into the binary. Override it for development:

```bash
inlay list --registry ../registry.json          # local path
INLAY_REGISTRY=https://…/registry.json inlay list   # remote
```

## Commands

| Command | What it does |
| --- | --- |
| `inlay init` | Detects your `.xcodeproj`, creates the `Inlay/` folder, writes `inlay.lock.json`, and reports whether the project uses Xcode 16 buildable folders. |
| `inlay add <name> [--variant <id>] [--manual] [--dry-run]` | Resolves `<name>` + its dependencies (topological order) and writes each file **into the project's synchronized source folder** (so it auto-builds — no `mv` or manual target edits), updates the lockfile, and prints a usage snippet. Already-installed pieces are skipped. Paths are sanitized (no `..`/absolute escapes). `--manual` prints source + paste instructions; `--dry-run` prints the plan without writing. A typo'd name gets git-style "did you mean" suggestions. |
| `inlay list` | Lists components grouped by category, marking installed ones. |
| `inlay search <query>` | Fuzzy-searches names, titles, descriptions, and categories. |
| `inlay diff <name>` | Shows a unified diff between your installed copy and the registry source. |
| `inlay update [<name>] [--yes]` | Re-applies the registry version of installed components. Without `--yes` it only reports diffs (never silently overwrites edits); with `--yes` it applies them and updates the lockfile. |
| `inlay remove <name> [--force] [--dry-run]` | Deletes a component's files and updates the lockfile. Refuses if another installed component still depends on it, or if you edited the files, unless `--force`. Surfaces now-orphaned dependencies. |
| `inlay doctor` | Diagnoses setup: Xcode version, buildable-folder status, install base, deployment-target vs each component's `minIOS`, registry reachability, and whether installed files are present on disk. |

## inlay.lock.json

Records what's installed so two components that both need `spring-animator`
never double-install it. Each entry stores the files written, the chosen variant
(if any), and a content hash used to detect drift.

## Keeping the bundled registry fresh

The CLI ships `Sources/inlay/Resources/registry.json`. Regenerate it from the
registry source with:

```bash
../scripts/sync-registry.sh
```

## Distribution (Homebrew tap)

A formula template lives at [`Formula/inlay.rb`](Formula/inlay.rb). To ship:

1. Create a tap repo, e.g. `github.com/<org>/homebrew-tap`.
2. Tag a release of this repo and attach the built binary (or let the formula
   build from source).
3. Drop the formula into the tap, fill in the `url`/`sha256`, and users run
   `brew install <org>/tap/inlay`.
