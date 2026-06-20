# Inlay — Design Details

This document is the *why*. It records the decisions behind the architecture so
that every future component and every line of the CLI stays consistent. Read it
before adding components or changing conventions.

---

## 1. Theming — self-contained first, shared tokens optional

**The problem.** shadcn/ui components depend on shared Tailwind/CSS-variable
tokens; paste one without running `init` and it's broken. That's fine on the
web. Inlay's headline flow is "search *one* component, run *one* command, it
runs." A hard dependency on a separate `Theme.swift` would mean a single pasted
component won't compile until the user also sets up the theme — which kills the
magic.

**The decision.** Every component is **self-contained** and runs with zero
setup. Customization happens through a **nested `Configuration` struct** with
baked-in defaults:

```swift
final class FloatingToolbar: UIView {
    struct Configuration {
        var accentColor: UIColor = .tintColor
        var cornerRadius: CGFloat = 28
        var animation: Inlay.Spring = .lively
        // …
        static let `default` = Configuration()
    }
    init(items: [Item], configuration: Configuration = .default) { … }
}
```

This single pattern does three jobs:
- pastes in and runs with zero config (defaults baked in),
- makes customization uniform across all components ("set these properties"),
- makes the website's *how-to-customize* docs auto-generatable — every
  component documents the same shape.

**Shared design tokens** (colors, spacing, type scale, and animation springs)
live under the `Inlay` namespace and are an **opt-in upgrade**: a user who
installs many components can `inlay init` to get one tokens file, and component
defaults may reference it. A lone component never needs it.

**Animation tokens are first-class.** `Inlay.Spring` is a shared token, not a
per-component type, because animation is the product's differentiator. Reusing
one spring vocabulary across every component is what makes the library feel
designed.

**Dark mode** is automatic: use dynamic `UIColor` (`.systemBackground`, asset
colors, `withAlphaComponent` on system colors), never hard-coded RGB.

---

## 2. Dependencies — zero external, internal graph, install-once

**Rule:** components depend only on UIKit/Foundation and on other Inlay registry
pieces (copied in). **Never** an external SPM package — auto-adding a package is
the one thing still fragile on iOS.

UIKit components aren't single files, so there *is* an internal dependency
graph. `floating-toolbar` depends on the `spring-animator` primitive. The CLI:
1. reads the component's `dependencies`,
2. topologically resolves them,
3. copies each piece to its destination,
4. **skips anything already installed** (checked against `inlay.lock.json`),
   so two components that both need `spring-animator` never double-install it.

### The Swift collision trap (critical)

In Swift, **top-level type names are global within the app's module.** Two
components each declaring a top-level `struct Configuration`, or each bringing a
top-level `BlurView`, will fail to compile (duplicate declaration). JS has file
scoping; Swift does not. Two mandatory defenses:

1. **Nest per-component helper types inside the component**
   (`FloatingToolbar.Configuration`, `FloatingToolbar.Item`) — namespaced,
   collision-proof.
2. **Shared primitives nest under `enum Inlay {}`** (`Inlay.Spring`,
   `Inlay.SpringAnimator`) and install once.

User-facing component classes (`FloatingToolbar`) stay top-level for ergonomics;
their names are distinctive enough to rarely collide with app code, and the user
owns the file so they can rename if needed.

Note: everything lands in the user's own module, so `public` is unnecessary —
default (internal) access is correct throughout.

---

## 3. UIKit-first execution

UIKit is the right first target: it's explicit, programmatic, fully
controllable — exactly what someone wants when they own and customize the code —
and custom UIKit animation is the most painful iOS boilerplate, so the value of
"don't write this again" is highest there.

**Conventions every component follows** (so all ~50 feel like one system):
- `init(… , configuration: Configuration = .default)`.
- Programmatic Auto Layout; `translatesAutoresizingMaskIntoConstraints = false`.
- A nested `Configuration` with a `.default`, and nested model types
  (`Item`, etc.).
- Callbacks via closures (or a delegate for richer components).
- Shadow on the outer view (no clip); corner-radius/clip on an inner container —
  shadows and `clipsToBounds` can't share a layer.
- Set `layer.shadowPath` in `layoutSubviews()`.
- `layer.cornerCurve = .continuous` for the modern squircle look.
- One animation vocabulary: `Inlay.Spring` + `Inlay.SpringAnimator`.
- iOS 16 floor; SF Symbols for icons.

**Variants.** Prefer expressing a variant as a `Configuration` option of *one*
component (DRY, one file) — e.g. glass vs solid is a `background` case. Only
split into separate registry entries when the code genuinely diverges
(different layout or animation engine). The floating-toolbar manifest lists
glass / solid / tinted as config-driven variants.

---

## 4. The distribution loop

```
   Real Swift in /registry  ──(generator script)──►  registry.json + raw files
                                                            │
                              website gallery ◄────────────┤
                                                            │
   user runs `inlay add X` ──► CLI fetches manifest ──► resolves deps
        ──► dedupes via inlay.lock.json ──► writes into Inlay/ buildable folder
        ──► compiles instantly ──► user customizes via Configuration
```

The source of truth is **compilable code**, so components never rot. The
registry is a build artifact. The website and CLI both read the same artifact.

---

## 5. Auto-placement vs manual paste

**Default (auto):** the CLI owns the destination — it creates/uses an `Inlay/`
folder configured as an Xcode **buildable folder**, so any file dropped in is
auto-included in the build with no `.pbxproj` edits. The user never types a
filename; the manifest's `to` paths decide placement.

**Fallback (manual):** every component page also shows the raw source to
copy-paste, for users on older Xcode or unusual project setups. If the CLI
detects the target isn't a buildable folder, it still writes the files and
prints a one-line note on how to add the folder to the target.
