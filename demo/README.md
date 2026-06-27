# InlayDemo

A tiny UIKit app that compile-tests the registry components and showcases the
`floating-toolbar` (all three variants, live-switchable).

The demo pulls the **real registry source** from `../../registry` — there are no
copies, so the demo can never drift from what the CLI ships. This is how we
satisfy CLAUDE.md's "build & test" step without an external dependency.

## Run it

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen          # once
cd demo/InlayDemo
xcodegen generate              # writes InlayDemo.xcodeproj
open InlayDemo.xcodeproj       # ⌘R on an iOS 16+ simulator
```

Or build headless:CLI.md

```bash
xcodebuild -project InlayDemo.xcodeproj -scheme InlayDemo \
  -destination 'generic/platform=iOS Simulator' build
```

## What to verify

Follow `docs/FLOATING_TOOLBAR_TEST.md`. In short: the toolbar fades + springs
in from 80% scale, presses scale icons with a light haptic, the selection pill
slides behind the last-tapped icon, and the segmented control at the top swaps
between the Glass / Solid / Tinted variants. Toggle the simulator to Dark Mode
and rotate to landscape — both should adapt.
