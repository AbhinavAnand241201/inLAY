# CLAUDE.md — Build spec for Inlay

You are building **Inlay**, a copy-paste UIKit component distribution for iOS
("shadcn/ui for iOS"). Read `ROADMAP.md` and `DETAILS.md` first; this file is the
implementation contract. Follow it exactly — the conventions are load-bearing.

---

## Non-negotiable rules

1. **Components are self-contained.** A single pasted component file must compile
   with **zero setup**, except for its declared registry dependencies (which the
   CLI copies in). Never require an external SPM package.
2. **100% programmatic UIKit.** No storyboards, no nibs, no Interface Builder.
3. **Collision safety:** shared primitives nest under `enum Inlay {}`
   (`Inlay.Spring`). Per-component helper types nest inside the component
   (`FloatingToolbar.Configuration`). Never declare a generic top-level helper
   type (`Configuration`, `BlurView`, `Animator`) — it will clash in the user's
   module.
4. **Default (internal) access** everywhere — everything lands in the user's
   module; `public` is wrong here.
5. **The registry is generated**, never hand-edited. Components are real,
   compiling Swift; the generator produces `registry.json`.
6. iOS deployment target **16.0**, Swift **5.9+**.

---

## Repo layout (monorepo)

```
inlay/
├── ROADMAP.md
├── DETAILS.md
├── CLAUDE.md
├── registry/                      # source of truth — real Swift
│   ├── spring-animator/
│   │   ├── Inlay+SpringAnimator.swift
│   │   └── manifest.json
│   └── floating-toolbar/
│       ├── FloatingToolbar.swift
│       └── manifest.json
├── demo/                          # Xcode app target that imports the registry
│   └── InlayDemo/ …               #   files via a buildable folder, for testing
├── cli/                           # the `inlay` CLI (Swift, swift-argument-parser)
│   ├── Package.swift
│   └── Sources/inlay/ …
├── scripts/
│   └── build-registry.swift       # registry/ -> registry.json
├── registry.json                  # generated artifact (CLI + website read this)
└── website/                       # gallery (Next.js or Astro), reads registry.json
```

---

## Manifest schema (per component, hand-authored alongside source)

```jsonc
{
  "name": "floating-toolbar",         // unique id, kebab-case, == CLI arg
  "kind": "uikit",                    // uikit | swiftui | primitive
  "title": "Floating Toolbar",
  "description": "…",
  "category": "navigation",
  "minIOS": "16.0",
  "swiftVersion": "5.9",
  "files": [
    { "from": "registry/floating-toolbar/FloatingToolbar.swift",
      "to":   "Inlay/Components/FloatingToolbar.swift" }
  ],
  "dependencies": ["spring-animator"], // other registry names, resolved + copied
  "variants": [                        // config-driven previews on the website
    { "id": "glass", "title": "Glass", "description": "…",
      "config": { "background": "glass(.systemThinMaterial)" } }
  ]
}
```

`to` paths define placement inside the user's project. Primitives go to
`Inlay/…`; components to `Inlay/Components/…`.

---

## `scripts/build-registry.swift`

- Walk `registry/*/manifest.json`.
- For each, read every `from` file, capture its raw source text.
- Validate: file exists; `dependencies` all resolve to known names; no dependency
  cycles (topological sort must succeed).
- Emit `registry.json`:

```jsonc
{
  "version": 1,
  "components": [
    {
      "name": "floating-toolbar",
      "kind": "uikit", "title": "…", "description": "…",
      "category": "navigation", "minIOS": "16.0",
      "dependencies": ["spring-animator"],
      "variants": [ … ],
      "files": [
        { "to": "Inlay/Components/FloatingToolbar.swift",
          "source": "<raw swift text>" }
      ]
    }
  ]
}
```

The website and CLI consume only `registry.json` (or fetch raw files from GitHub
raw URLs — start with whichever is simpler; embedding source in `registry.json`
is fine at this scale).

---

## The CLI (`cli/`, Swift + swift-argument-parser)

Distribute via a Homebrew tap. Commands:

### Install-base resolution (Xcode 16 buildable folders — load-bearing)

Xcode 16 projects use **synchronized source folders**
(`PBXFileSystemSynchronizedRootGroup` in `project.pbxproj`): the contents of the
inner source folder (typically named after the project, e.g. `TestApp1/`) build
automatically. A new project's root directory — where the `.xcodeproj` lives and
where the user runs `inlay` — is *not* that folder. So writing components to the
project root means they don't compile until the user manually drags `Inlay/` into
the target.

**Rule: components install into the synchronized source folder, never the root.**
The CLI parses `project.pbxproj` for synchronized-root paths, picks the app's
source folder (prefer the one named after the project; skip `*Tests` folders),
and writes each `file.to` *inside* it — e.g. `TestApp1/Inlay/Components/Foo.swift`.
That folder already builds, so `inlay add` compiles with zero project edits.

- The **install base** is this source folder, relative to the project root.
- `inlay.lock.json` stays at the project root but records each file's **real**
  path (base + `file.to`), so `diff`/`list` find the installed copies.
- Fallbacks: a classic (non-synchronized) project, an undetectable source folder,
  or no `.xcodeproj` → write to `Inlay/` at the root and print exactly how to add
  it to the target. (Validated by the demo in §Build & test.)

### `inlay init`
- Detect the Xcode project (`*.xcodeproj`) in the working dir and resolve the
  install base (see above).
- Create the `Inlay/` folder **inside the install base** (e.g.
  `TestApp1/Inlay/`). Tell the user where components will land and whether they
  auto-build; for a classic project, print exactly how to add `Inlay/` to the
  target.
- Write `inlay.lock.json` (empty installed list) and optionally a shared tokens
  file if/when one exists.

### `inlay add <name> [--variant <id>] [--manual]`
1. Load `registry.json` (bundled or fetched).
2. Resolve `<name>` + its `dependencies` transitively (topological order).
3. Resolve the install base from the detected project (synchronized source
   folder, else root).
4. For each resolved piece, check `inlay.lock.json`:
   - already installed at the same version → **skip** (prevents duplicate
     `Inlay.SpringAnimator` etc.).
   - not installed → write each `file.to` under the install base with
     `file.source`.
5. Update `inlay.lock.json` (recording real on-disk paths).
6. Print: where files landed (and that the folder auto-builds), the dependency it
   pulled in, and a 3-line usage snippet (from the manifest, if present).
7. `--manual`: don't write files; print the raw source + paste instructions.

### `inlay list`
- Print available components grouped by category, marking installed ones.

### `inlay diff <name>`
- Compare the installed file against the registry source; show changes the user
  made (so updates never silently clobber customizations). Full `update` can
  come later — `diff` first.

### `inlay.lock.json`
```jsonc
{
  "version": 1,
  "installed": [
    // Paths are the real on-disk locations — inside the synchronized source
    // folder when one is detected (here the app folder is `TestApp1`).
    { "name": "spring-animator",  "files": ["TestApp1/Inlay/Inlay+SpringAnimator.swift"],
      "hash": "…" },
    { "name": "floating-toolbar", "files": ["TestApp1/Inlay/Components/FloatingToolbar.swift"],
      "variant": "glass", "hash": "…" }
  ]
}
```

---

## Component coding conventions (apply to every component you write)

- `final class <Name>: UIView` (or `UIControl`); programmatic only.
- Nested `Configuration` with a `static let default`, and a designated
  `init(… , configuration: Configuration = .default)`.
- Nested model types (`Item`, etc.). Callbacks via closures.
- Auto Layout; set `translatesAutoresizingMaskIntoConstraints = false`.
- Shadow on the outer view (no clip); corner-radius + `clipsToBounds` on an inner
  container view. Set `layer.shadowPath` in `layoutSubviews()`.
- `layer.cornerCurve = .continuous`.
- Animations only via `Inlay.Spring` + `Inlay.SpringAnimator`.
- Dynamic/system colors for automatic dark mode; never hard-coded RGB.
- Header comment block: what it is, a runnable usage snippet, and the
  `Dependency:` line. See `registry/floating-toolbar/FloatingToolbar.swift` as
  the canonical reference — match its structure for every new component.

---

## Build & test (must pass before any component is "done")

The demo app is how we verify, since UIKit only builds on macOS/Xcode:

1. `demo/InlayDemo` references `registry/` files through a buildable folder.
2. Build for an iOS 16+ Simulator; zero warnings ideally, zero errors required.
3. Place the component on screen; verify entrance animation, press feedback,
   selection highlight, dark-mode appearance, and dynamic-type/safe-area layout.
4. Then run `docs/FLOATING_TOOLBAR_TEST.md` (the usability pass).

---

## Build order

1. `spring-animator` (done — see registry/).
2. `floating-toolbar` (done — see registry/).
3. `scripts/build-registry.swift` → produce `registry.json`.
4. `demo/InlayDemo` to compile-test 1 & 2.
5. The CLI (`init`, `add`, `list`, `diff`) + Homebrew tap.
6. The website reading `registry.json`.

Start at step 3. Steps 1–2 already exist in `registry/`; treat them as the
reference style for everything else.
