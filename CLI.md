# CLI.md — The Inlay CLI: build, test, ship, scale

This is the full technical design for `inlay`, the command-line tool that installs
Inlay components into a Swift developer's project. It is written to be handed to
Claude Code as a build contract and to you as a decision document. It deliberately
front-loads the edge cases, because the bugs in a tool like this live in the
seams: project detection, file placement, partial downloads, and version drift.

> **Mental model.** `inlay` never adds a runtime dependency and never executes
> remote code. It fetches plain `.swift` source from a registry and writes those
> files into the user's project. That's it. Everything else is correctness,
> safety, and developer experience around that one act.

---

## 0. Two ways to ship this — pick the phase

- **Phase 0 (optional, days):** distribute components through shadcn's existing,
  framework-agnostic CLI + a GitHub registry. Zero CLI to build. Costs you Node
  as a dependency and shadcn branding, but validates demand immediately.
- **Phase 1+ (this document):** build the native `inlay` CLI in Swift. Best
  experience for iOS devs (`brew install`, no Node), full control. The rest of
  this doc assumes you're building it.

Build the native CLI in **stages** (see §13). Do not attempt every feature at
once; the MVP is `init` + `add` done correctly.

---

## 1. System architecture

Five moving parts:

1. **Registry source** — real, compiling Swift in the monorepo's `registry/`.
2. **Registry artifacts** — generated JSON the CLI consumes:
   - `index.json` — lightweight list: `{name, version, kind, category, minIOS}`.
   - `r/<name>.json` — per-component item: metadata + dependencies + file list +
     **per-file source + per-file sha256**.
   Splitting a small index from heavy per-item files keeps `list`/`search` fast
   and downloads minimal.
3. **Registry host** — a CDN-fronted static file host (see §11). HTTPS only.
4. **The `inlay` CLI** — a Swift executable (SwiftPM + swift-argument-parser).
5. **Per-project state** — `inlay.json` (config) and `inlay.lock.json` (lockfile)
   written into the user's project.

Data flow: `registry/` → generator → `index.json` + `r/*.json` → CDN → CLI fetch
→ resolve deps → verify checksums → atomic write → update lockfile.

---

## 2. Tech stack & project layout

- **Language:** Swift 5.9+, built with SwiftPM as an executable target.
- **Arg parsing:** `swift-argument-parser`.
- **Networking:** `URLSession` (async/await). No third-party HTTP lib needed.
- **JSON:** `Codable`.
- **Hashing:** `CryptoKit` (`SHA256`).
- **Optional, advanced:** `tuist/XcodeProj` for the pbxproj-editing fallback
  (§5). Keep it optional and isolated — it's the one fragile dependency.

```
cli/
├── Package.swift
├── Sources/inlay/
│   ├── main.swift               # entrypoint, root command
│   ├── Commands/                # Init, Add, List, Search, Diff, Update, Remove, Doctor
│   ├── Registry/                # fetch, decode, cache, index
│   ├── Resolver/                # dependency graph + topo sort
│   ├── Project/                 # detect xcodeproj/spm, placement, buildable folder
│   ├── IO/                      # atomic writes, hashing, path sanitization
│   ├── Model/                   # Config, Lockfile, Manifest, Component
│   └── UI/                      # colored output, prompts, spinners, errors
└── Tests/inlayTests/
```

---

## 3. Command surface

| Command | Purpose |
|---|---|
| `inlay init` | Detect the project, create `Inlay/` destination + `inlay.json` + empty `inlay.lock.json`, run setup checks. |
| `inlay add <name…>` | Install one or more components + their deps. Core command. |
| `inlay list` | Show available components (from `index.json`), marking installed ones. |
| `inlay search <query>` | Fuzzy search names/descriptions/categories. |
| `inlay diff [<name>]` | Show how installed files differ from the registry version (detects your edits and upstream changes). |
| `inlay update [<name>]` | Pull newer versions; never silently overwrite edits — show diff, require confirm. |
| `inlay remove <name>` | Delete a component's files (with edit/refcount safety), update lockfile. |
| `inlay doctor` | Diagnose setup: Xcode version, buildable-folder status, deployment-target vs minIOS, registry reachability. |
| `inlay --version` / `--help` | Standard. |

**Global flags:** `--path <dir>` (project root), `--registry <url>` (override),
`--yes` (non-interactive/CI), `--dry-run` (print actions, write nothing),
`--manual` (print source instead of writing), `--no-color`, `--verbose`.

`add` flags: `--variant <id>`, `--overwrite`, `--target <name>`.

---

## 4. Config & lockfile formats

`inlay.json` (project config, created by `init`):
```jsonc
{
  "schemaVersion": 1,
  "registry": "https://cdn.inlay.dev",     // base URL; index at /index.json, items at /r/<name>.json
  "destination": "Inlay",                   // folder, relative to project root
  "projectType": "xcodeproj",               // xcodeproj | workspace | spm
  "projectPath": "MyApp.xcodeproj",
  "target": "MyApp",                         // resolved target/module (optional for spm)
  "deploymentTarget": "16.0"                 // cached from project for minIOS checks
}
```

`inlay.lock.json` (what's installed; source of truth for idempotency/diff/remove):
```jsonc
{
  "schemaVersion": 1,
  "installed": [
    {
      "name": "spring-animator",
      "version": "1.0.0",
      "files": [{ "path": "Inlay/Inlay+SpringAnimator.swift", "sha256": "…" }],
      "dependents": ["floating-toolbar"]     // refcount for safe removal
    },
    {
      "name": "floating-toolbar",
      "version": "1.2.0",
      "variant": "glass",
      "files": [{ "path": "Inlay/Components/FloatingToolbar.swift", "sha256": "…" }],
      "dependents": []
    }
  ]
}
```

Both are committed to the user's git. The lockfile's stored `sha256` per file is
what powers "did the user edit this?" (compare current file hash to lockfile hash)
and "did upstream change?" (compare registry hash to lockfile hash).

---

## 5. The hard part: getting files into the build

Writing a `.swift` file to disk is **not** the same as adding it to the Xcode
target. This is the #1 source of silent failure ("I installed it but Xcode
doesn't see it"). Three placement strategies, in order of preference:

### 5a. Buildable folder (Xcode 16+) — the default, recommended
Xcode 16 introduced **file system synchronized groups** ("buildable folders"):
a folder reference whose contents are auto-included in the target. Once `Inlay/`
is a buildable folder, every future `inlay add` just writes files — no project
edits, no merge conflicts.

The catch: the folder must be registered **once**. Two ways:
- **Manual (safest):** `inlay init` creates `Inlay/` on disk and instructs the
  user to drag it into Xcode once (Xcode 16 adds new folders as buildable by
  default). One-time, zero pbxproj risk. Recommend this as the default path.
- **Automated (advanced, optional):** the CLI edits the pbxproj to add a
  `PBXFileSystemSynchronizedRootGroup` for `Inlay/` via `XcodeProj`. Faster, but
  pbxproj edits are fragile and merge-hostile. Gate behind `--auto-xcode` and
  always back up the pbxproj first.

`inlay doctor` must verify the folder is actually a buildable folder in the
chosen target; if not, print exact fix steps. This converts the silent failure
into a loud, actionable one.

### 5b. SwiftPM package — detect and place in `Sources/`
If the project root has `Package.swift` and no `.xcodeproj`, it's an SPM package.
Files go under the target's `Sources/<Target>/Inlay/…`; SwiftPM auto-includes all
`.swift` under a target, so no project edit is needed. Detect the target from
`Package.swift` (or ask if multiple).

### 5c. Legacy fallback (Xcode 15 and earlier)
Buildable folders don't exist. Options: (a) use `XcodeProj` to add each file as an
individual `PBXFileReference` + build-file entry to the target, or (b) write the
files and print precise "add these to your target" instructions. Detect Xcode
version via `xcodebuild -version`; if < 16 and not SPM, warn loudly and use (a)
or (b). **Never** claim success if the files aren't in the build.

---

## 6. Core algorithms

### 6a. Dependency resolution (topological)
1. Fetch `r/<name>.json` for each requested component.
2. Recursively fetch each `dependencies[]` item, building a graph.
3. **Detect cycles** (DFS with a visiting/visited set) → hard error naming the
   cycle (registry-author bug, but defend against it).
4. **Detect missing deps** (a name not present in the registry) → hard error.
5. Topologically sort so primitives are written before the components that use
   them. Order doesn't matter for compilation (one module) but matters for clean
   rollback and clear output.

### 6b. Atomic, transactional install (critical for correctness)
Never leave a half-installed project. Sequence:
1. Resolve the full set of files to write.
2. Download **all** sources to a temp staging dir.
3. Verify **every** file's sha256 against its manifest value. Any mismatch →
   abort, nothing touched.
4. Pre-flight collision check against existing files + lockfile (see 6c).
5. Move staged files into place. If a move fails midway, **roll back** the moves
   already done (restore from a pre-write backup of any overwritten files).
6. Update `inlay.lock.json` last, under a file lock (see edge cases), then fsync.

If any step before 5 fails, the project is untouched. If 5 fails, it's restored.

### 6c. Idempotency & edit detection
For each file to write:
- If not present and not in lockfile → write.
- If present and lockfile hash == current file hash (unmodified) → overwrite
  silently with the new version (safe; user never touched it).
- If present and current hash != lockfile hash → **user edited it**. Do not
  clobber. Print a diff and require `--overwrite` or a prompt.
- If present but not in the lockfile (user has their own file by that name) →
  treat as a collision; prompt / require `--overwrite`.

### 6d. Path sanitization (security-critical)
Every destination path from a manifest must be validated:
- Reject absolute paths, reject any component equal to `..`, reject paths that,
  once resolved, escape the project root or the configured `destination`.
- Normalize separators; resolve symlinks and re-check containment.
- Create intermediate directories as needed.
A malicious or buggy manifest must never write outside `destination`.

---

## 7. Edge cases & failure modes (the catalog)

### Project & placement
- No project found in cwd → clear error; suggest `--path` or `cd`.
- **Multiple** `.xcodeproj`/`.xcworkspace` → ambiguous; require `--path`/prompt.
- Workspace with several projects/targets → resolve target in `init`, store it.
- Multiple targets, component needed in one → respect `target`; allow `--target`.
- Case-insensitive macOS filesystem: `FloatingToolbar.swift` == `floatingtoolbar.swift`.
  Treat name collisions case-insensitively to avoid "two files, one on disk."
- Destination folder missing → create it (and parents).
- File exists & modified by user → never clobber (see 6c).
- Project in a read-only / permission-restricted location → catch write errors,
  surface a clean message.
- Files written but folder isn't a buildable folder / in target → `doctor` must
  catch; `add` should warn if it can detect the folder isn't registered.

### Dependencies & versions
- Circular deps → detect + error (6a).
- Missing dep → error (6a).
- Diamond deps, same version → install shared piece once (refcount in lockfile).
- **Version conflict:** installed `spring-animator@1` but new component needs
  `@2` with a breaking change → do not silently replace. Warn, show what changed,
  require explicit confirm; offer to keep `@1` if compatible. Drive this with a
  documented SemVer policy (§12).
- Shared primitive edited by the user, then a component needs a newer version →
  conflict between "your edits" and "required upgrade" → surface both, never
  auto-resolve.

### Network & registry
- Offline / DNS failure → clear error; fall back to a local cache of the last
  good registry if present (read-only mode).
- Registry 404/410 for a name (renamed/removed component) → explain, suggest
  `inlay search`.
- 5xx / timeout → retry with exponential backoff (e.g. 3 tries), then fail.
- **Partial / corrupted download** → checksum mismatch → re-download once, then
  abort. Never write an unverified file.
- Registry `schemaVersion` newer than the CLI understands → warn and ask the user
  to `brew upgrade inlay`; refuse rather than misparse.
- Index grown large → already mitigated by index/item split; consider gzip and
  HTTP caching (ETag/If-None-Match) to avoid re-downloading unchanged index.
- GitHub raw rate limits if hosting there → use a CDN (§11) to avoid.

### CLI distribution & runtime
- No Homebrew → offer Mint, a curl installer, or a direct GitHub Release binary.
- Apple Silicon vs Intel → ship a **universal2** binary (or build-from-source via
  brew, which sidesteps arch entirely).
- **Gatekeeper/quarantine** on a downloaded unsigned binary → either build from
  source in the Homebrew formula (no notarization needed) or **notarize** the
  binary (needs the $99/yr Apple Developer Program). Recommend build-from-source
  first; notarize only if you ship prebuilt binaries.
- Swift toolchain absent (only if building from source) → nearly all iOS devs
  have Xcode/CLT; document the requirement; prefer prebuilt to avoid it if you
  notarize.
- PATH not updated after install → Homebrew handles; document for manual installs.

### Concurrency & integrity
- Two `inlay` processes writing the lockfile at once → take an exclusive **file
  lock** on `inlay.lock.json` for the write section; fail fast if locked.
- Process killed mid-write → atomic staging (6b) means the project is consistent;
  a stale temp dir is cleaned on next run.
- Line endings/encoding → write UTF-8, LF, no BOM; normalize on read for hashing
  so CRLF checkouts don't false-trigger "edited."

### DX papercuts (each one prevents a support ticket)
- Typo'd component name → suggest nearest match (Levenshtein) like git.
- `add` before `init` → auto-init with a confirmation, or a clear prompt.
- Deployment target < component `minIOS` → warn before writing, with the numbers.
- `--dry-run` shows the full plan (files, deps, conflicts) without touching disk.
- Progress + clear success summary: what was added, where, and a usage hint.
- Non-zero exit codes per failure class (for scripting/CI).

---

## 8. Security model

- **No code execution.** The CLI only writes `.swift` files; it never runs
  install scripts. State this as a guarantee; never add post-install hooks.
- **HTTPS-only**, pinned to the registry host; reject plaintext.
- **Checksums** on every file; the lockfile records them; tampered or corrupted
  files are rejected.
- **Path traversal** blocked (6d).
- **Supply chain:** the registry is generated from the public monorepo in CI;
  consider signing `index.json` (e.g. minisign) later so clients can verify
  authenticity, not just integrity.

---

## 9. Testing strategy

The whole point of the tool is "the file lands and **compiles**." Test that.

- **Unit tests:**
  - Resolver: topo order, cycle detection, missing dep, diamond/refcount.
  - Path sanitization: rejects `..`, absolute, symlink-escape, accepts valid.
  - Lockfile/config: encode/decode round-trip; forward-compat with unknown keys.
  - Hashing + edit detection; CRLF/LF normalization.
  - Manifest decoding incl. malformed JSON and unknown `schemaVersion`.
  - Name fuzzy-match suggestions.
- **Integration tests (fake registry):** serve `index.json` + `r/*.json` from a
  temp dir via `file://` or a local HTTP server. Run `add`; assert files written,
  checksums verified, lockfile updated, idempotent re-run is a no-op, and a
  simulated mid-write failure rolls back cleanly.
- **End-to-end (the real test):** keep fixture projects in the repo — one
  `.xcodeproj` app and one SPM package. In CI on a **macOS runner**, run
  `inlay add floating-toolbar` against the fixture, then `xcodebuild build` for an
  iOS 16 simulator and assert it compiles. This is what proves a component +
  the CLI actually work together. Run it for every component.
- **Matrix:** at minimum two Xcode versions (one with buildable folders, one
  without) and SPM vs xcodeproj.
- **Snapshot tests** of CLI output for stable UX.

---

## 10. CI/CD & release pipeline

GitHub Actions (macOS runners):
1. **On PR:** build the CLI, run unit + integration + e2e (`xcodebuild`) tests,
   regenerate `index.json`/`r/*.json` from `registry/` and **validate** (schema,
   no dependency cycles, every file hashes, every `minIOS` present).
2. **On tag `vX.Y.Z`:**
   - Build a release binary (universal2). Optionally notarize.
   - Create a GitHub Release with the binary + checksums.
   - **Auto-bump the Homebrew formula** in the tap repo (new `url`, new `sha256`)
     via a bot commit/PR.
   - Deploy the regenerated registry artifacts to the CDN/host.

Tag the registry content with the same git tags so versioned, immutable URLs are
available for caching.

---

## 11. Distribution & global accessibility

Two things must be globally fast and reliable: the **CLI binary** and the
**registry**.

- **CLI via Homebrew tap (primary).** A tap is just a public GitHub repo named
  `homebrew-tap`. Users run `brew install <org>/tap/inlay`. GitHub is globally
  reachable; Homebrew handles arch. **Build-from-source formula** avoids
  notarization entirely — simplest first path.
- **Also offer:** Mint (`mint install <org>/inlay`) for Swift-native folks, a
  one-line `curl … | bash` installer that pulls the right GitHub Release binary,
  and direct binary downloads. More install paths = fewer blocked users.
- **Registry via CDN (for global latency).** Host `index.json` + `r/*.json` on a
  global edge: Cloudflare Pages/R2, or **jsDelivr** (free CDN that mirrors a
  GitHub repo/tag with worldwide caching). Either gives low latency on every
  continent and sidesteps GitHub raw's rate limits. Use immutable, tag-versioned
  URLs so the CDN caches aggressively; bust cache on release.
- **Custom domain optional.** `cdn.inlay.dev` is nicer than a vendor URL but not
  required to launch (a `*.pages.dev` / jsDelivr URL works on day one).

Net effect: a developer in any region runs `brew install …` then `inlay add …`,
and both the tool and the components come from edge-cached, globally available
infrastructure.

---

## 12. Versioning & compatibility policy

- Every component and primitive has a **SemVer** version in its manifest.
- **Patch/minor** of a shared primitive must be backward compatible; `update`
  applies them freely (respecting user edits via diff).
- **Major** = breaking; `update`/`add` must warn and require confirmation, and
  the changelog must say what broke. Components declare the **major** they need.
- The CLI has its own version; `index.json`/items carry `schemaVersion`. A CLI
  refuses (with an upgrade hint) rather than misparsing a newer schema.

---

## 13. Phased build plan

1. **MVP:** `init` + `add` (single component, deps, checksums, atomic write +
   rollback, path sanitization, lockfile) + `doctor`. Buildable-folder (manual
   registration) path only. One fixture e2e test compiling in CI.
2. **DX:** `list`, `search`, fuzzy suggestions, `--dry-run`, `--manual`,
   deployment-target warnings, nicer output.
3. **Lifecycle:** `diff`, `update`, `remove` (with refcount + edit safety).
4. **Reach:** SPM project support, legacy/`--auto-xcode` pbxproj path, Mint +
   curl installers, CDN + custom domain, optional notarized binaries.
5. **Hardening:** registry signing, schema-version negotiation, broader Xcode/OS
   test matrix.

Ship Phase 1 with exactly one component (floating-toolbar) end to end before
expanding. A correct, boring MVP beats a broad, flaky one.

---

## 14. Open decisions for you

- Registry host: **jsDelivr (zero-setup, free)** vs **Cloudflare (your domain,
  more control)**. Recommend jsDelivr to start.
- CLI distribution: **build-from-source brew formula (no Apple account)** vs
  **prebuilt notarized binaries ($99/yr, smoother UX)**. Recommend source first.
- Xcode integration default: **manual buildable-folder registration (safe)** vs
  **automated pbxproj editing (slick but fragile)**. Recommend manual default,
  automated behind a flag.
- Support SPM packages in v1, or Xcode app projects only first?