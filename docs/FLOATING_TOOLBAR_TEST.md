# Floating Toolbar — Test & Usability Pass

This is the on-device test for the first component. UIKit only compiles on a Mac
with Xcode, so these steps run on your machine.

## A. Quick visual test (5 min)

1. New Xcode project → **iOS App**, Interface = **Storyboard** or **SwiftUI**
   (doesn't matter), language **Swift**, deployment target **iOS 16**.
2. Drag `Inlay+SpringAnimator.swift` and `FloatingToolbar.swift` into the
   project (check "Copy items if needed", add to the app target).
3. Replace your root view controller with the one below (or paste into your
   existing `viewDidLoad`).

```swift
import UIKit

final class DemoViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let toolbar = FloatingToolbar(items: [
            .init(icon: UIImage(systemName: "house.fill"))      { print("home") },
            .init(icon: UIImage(systemName: "magnifyingglass")) { print("search") },
            .init(icon: UIImage(systemName: "bell.fill"))       { print("alerts") },
            .init(icon: UIImage(systemName: "person.fill"))     { print("profile") },
        ])
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }
}
```

If you used a SwiftUI app, set it as the root via a `UIViewControllerRepresentable`,
or just make a Storyboard app and set this as the initial VC's class.

4. Run on an iPhone simulator.

**Expect:** the toolbar fades + springs in from 80% scale, sits centered above
the home indicator, blurs the background, scales each icon down on press with a
light haptic, and slides a tinted pill behind the last-tapped icon.

## B. Customization test (2 min)

Replace the toolbar creation with a customized config and re-run:

```swift
var config = FloatingToolbar.Configuration.default
config.accentColor = .systemPurple
config.background   = .solid(.secondarySystemBackground)
config.cornerRadius = 20
config.animation    = .playful

let toolbar = FloatingToolbar(items: [ /* same items */ ], configuration: config)
```

**Expect:** purple icons, opaque adaptive background, bouncier animation.

## C. Robustness checklist

- [ ] Toggle the simulator to **Dark Mode** — colors adapt, blur still reads.
- [ ] Rotate to landscape — stays centered, respects safe area.
- [ ] Tap rapidly — no flicker, selection pill keeps up, no crash.
- [ ] Add 6 items instead of 4 — spacing stays even.
- [ ] Build log: **0 errors** (warnings noted and triaged).

## D. The dumb-user usability pass (the real validation)

Hand the project + the website's component page to someone who writes iOS apps
but is *not* deeply technical. Without helping them, time the following:

- [ ] They find the floating toolbar on the website.
- [ ] They run the install command (later: `inlay add floating-toolbar`; for now,
      drag the two files in).
- [ ] They get it on screen using only the usage snippet.
- [ ] They change the accent color using only the website's customize steps.
- [ ] Total time **under 5 minutes**, no questions asked of you.

If they stall, **the stall point is your top backlog item** — note exactly where
and why. That single observation is worth more than any feature you could add.

## Known limitations (acceptable for v1, log for later)

- Selection pill is frame-animated; if items change while a selection is showing,
  re-tap to resync. Fine for v1.
- No accessibility labels yet — add `accessibilityLabel` from `Item.title`/icon
  before public launch.
