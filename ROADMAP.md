# Inlay — Roadmap

> **Inlay** is a copy-paste UIKit component & animation distribution for iOS —
> "shadcn/ui for iOS." Developers search a component on the website, run one
> terminal command, and the source lands in their Xcode project ready to
> customize. They **own the code**; Inlay is not a dependency they import.
>
> *(Name is provisional. Before committing, confirm `inlay` is free on Homebrew,
> npm, and as a GitHub org. Alternatives discussed: `forge`, `slate`, `mica`.)*

---

## The core promise

1. Find a component (e.g. a floating toolbar) on the website.
2. Pick one of 3–4 animated variants.
3. Copy one command → `inlay add floating-toolbar`.
4. The CLI writes the source into a dedicated `Inlay/` folder in the project.
   Because of **Xcode 16 buildable folders**, it compiles immediately — no
   project-file edits, no manual copy-paste.
5. Customize via a single `Configuration` struct, following the website's steps.

Manual copy-paste of the source stays available as a universal fallback.

---

## Guiding principles (do not violate)

- **Self-contained components.** A single pasted component compiles with zero
  setup. The shared theme is an *opt-in upgrade*, never a hard requirement.
- **Zero external dependencies.** Components use only UIKit/Foundation and other
  Inlay registry pieces (which get copied in). Never an SPM package.
- **100% programmatic.** No storyboards, no nibs. Code is the product.
- **The registry is generated, never hand-written.** Components live as real,
  compiling Swift; a script extracts the registry the CLI + website consume.
- **Collision-safe by construction.** Shared primitives nest under the `Inlay`
  namespace and install once; per-component types nest inside the component.

---

## Phases

### Phase 0 — Foundations (½ day)
- [ ] Lock the name; reserve Homebrew tap, npm name, GitHub org.
- [ ] Decide iOS floor (recommend **iOS 16**).
- [ ] Create the monorepo skeleton (see `CLAUDE.md` → Repo layout).

### Phase 1 — First component, end to end (this is the proof) (2–3 days)
- [ ] Ship `spring-animator` (shared primitive) and `floating-toolbar`.
- [ ] Build the demo app target and verify both run in the Simulator.
- [ ] Run the **usability test** in `docs/FLOATING_TOOLBAR_TEST.md`.
- [ ] Write the registry-generator script; produce `registry.json`.

### Phase 2 — The CLI (2–3 days)
- [ ] `inlay init`, `inlay add <name>`, `inlay list`, `inlay diff`.
- [ ] Dependency resolution + install-once lockfile (`inlay.lock.json`).
- [ ] Buildable-folder auto-placement; manual-paste fallback message.
- [ ] Distribute via a Homebrew tap (`brew install <org>/tap/inlay`).

### Phase 3 — The website / registry host (3–5 days)
- [ ] Searchable gallery; each component page = preview video per variant +
      the exact `add` command + visible source + auto-generated customize docs.
- [ ] Host `registry.json` + raw source files (GitHub raw is fine to start).

### Phase 4 — Launch the first component publicly (1 day)
- [ ] Publish floating-toolbar + spring-animator only. One great component beats
      fifty mediocre ones for a launch.
- [ ] Post to r/iOSProgramming, iOS Dev Weekly, Twitter/X, Hacker News.

### Phase 5 — Scale the catalog (ongoing)
- [ ] Build toward ~50 components/animations using floating-toolbar as the
      template. Each new component is repetition of a proven shape.
- [ ] Later: a SwiftUI track once the UIKit catalog has traction.

---

## Division of labour

- **You (configuration & setup):** project/account setup, Homebrew tap, domain &
  website hosting, App Store/dev account, design decisions, running the
  on-device tests, marketing.
- **Claude Code (implementation):** all Swift components, the CLI, the
  registry-generator, the website scaffolding — per `CLAUDE.md`.

---

## Definition of done for Phase 1 (the only thing that matters right now)

A non-technical-leaning iOS developer can, **without help**:
run `inlay add floating-toolbar`, see the file appear, build, drop the toolbar
on screen with ~6 lines, change its accent color, and ship it — in under
5 minutes. If that works, the idea is validated. Everything else is scale.
