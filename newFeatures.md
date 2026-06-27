# COMPONENTS.md — Catalog & build backlog

Every component follows the conventions in `CLAUDE.md` (nested `Configuration`,
programmatic UIKit, `Inlay.Spring`/`Inlay.SpringAnimator` for motion, dynamic
colors for dark mode, self-contained, iOS 16). Use the **built** ones as
pattern references when generating the rest.

Legend: ✅ built (in `registry/`) · 🟡 to build

---

## Animation / motion

### ✅ floating-toolbar
Pill toolbar, glass/solid, spring entrance, press haptics, selection highlight.
Reference for: layout + shadow/clip split + haptics + selection.

### ✅ paged-image-view
Swipeable image carousel, one image per page, bottom-center page dots, tap-to-jump.
Reference for: paging `UIScrollView` + `UIPageControl` + scroll-driven state.

### ✅ reveal-view
Rounded-rect **or** circle that springs from 0→100% from the center.
Covers both "box scales from center" and "circle scales from center".
Reference for: pure animation primitive + `reveal()`/`conceal()`/`toggle()` API.

### ✅ bouncing-loader
Buffering indicator: row of dots + a larger ball bouncing above them.
Reference for: repeating animation + auto start/stop on window changes.

---

## Buttons — 🟡 `inlay-button`
A single component, variants via `Configuration.style`:
- `.glass` (UIVisualEffectView background), `.transparent` (clear + tinted
  border), `.filled` (accent), `.soft` (accent at low alpha).
- Press effect via `Configuration.pressEffect`: `.scale`, `.ripple`
  (expanding circle from touch point, masked to bounds), `.glow` (brief shadow
  pulse). Build `.ripple` with a `CAShapeLayer` circle animated from the touch
  location; clip to the button's rounded bounds.
- Config: title, icon, style, pressEffect, cornerRadius, accentColor, `onTap`.
- Haptic on tap. New pattern: touch-point-aware ripple via Core Animation.

## Navigation

### 🟡 `home-tab-bar`
Custom bottom tab bar supporting **3, 4, or 5** tabs (count = items you pass).
- `Item`: icon, selectedIcon?, title, `onSelect`.
- Animated selection: the active tab's icon springs up slightly + tints accent;
  an underline or pill indicator slides between tabs (`Inlay.SpringAnimator`).
- Config: style `.icons` / `.iconsAndTitles`, indicator `.pill` / `.underline`
  / `.dot`, background `.glass` / `.solid`, accentColor.
- Expose `selectedIndex` + `onChange`. Don't manage view controllers — emit
  selection; the host swaps content. Reuse the shadow/clip split from
  floating-toolbar.

### 🟡 `splash-screen`
Generic launch animation built from the app's **initial letter**.
- `SplashView(letter: "I", configuration:)`. Draws the letter large and centered
  (a `UILabel` with a heavy rounded font, or a `CAShapeLayer` text path for a
  stroke-draw effect).
- Animation options via `Configuration.entrance`: `.fadeScale` (spring in),
  `.strokeDraw` (animate a `CAShapeLayer.strokeEnd` 0→1 to "write" the letter),
  `.maskReveal`. Then `onFinish` fires so the host pushes the home screen.
- Config: letter, font, color/gradient, background, duration, entrance.
- New pattern: `strokeEnd` draw-on animation + gradient text mask.

## Input

### 🟡 `search-bar`
Highly customizable search field.
- Config: placeholder, icon, cornerRadius, background `.glass`/`.solid`, accent,
  showsCancel, clearButton.
- Animated focus: on begin-editing the bar springs wider / lifts shadow / reveals
  a cancel button (`Inlay.SpringAnimator`); reverses on end.
- Callbacks: `onTextChange`, `onSubmit`, `onCancel`. Wrap a `UITextField`; debounce
  `onTextChange`. New pattern: focus-driven layout animation + debounce.

## Lists

### 🟡 `horizontal-scroller`
Highly customizable horizontal scrollable list.
- Generic over a cell view builder: `HorizontalScroller(items:, cellProvider:)`.
- Config: itemSize or self-sizing, spacing, sectionInsets, paging on/off,
  snapping, `.peek` (show a sliver of the next item).
- Built on `UICollectionView` with a horizontal flow/compositional layout.
- Optional scale/alpha falloff for off-center items (scroll-driven). `onSelect`.

### 🟡 `vertical-list`
Highly customizable vertical list.
- Generic cell builder over `UICollectionView` (compositional, vertical).
- Config: spacing, insets, separators on/off, `.insetGrouped`-style cards,
  swipe actions optional, pull-to-refresh optional.
- Entrance: rows fade/slide in with a small stagger on first appear
  (`Inlay.SpringAnimator`, capped so long lists don't lag). `onSelect`.

## Screens

### 🟡 `settings-screen`
A drop-in, highly customizable settings UI.
- Model-driven: `Section(title:, rows:)` where `Row` is `.toggle`, `.disclosure`,
  `.value`, `.button`, `.slider`, each with icon, title, subtitle, handler.
- Built on `vertical-list` (declare it as a registry dependency) with inset-grouped
  cards, SF Symbol tinted icons, and animated toggles.
- Config: card style, accent, icon background shape, row height.
- This is the first **composite** component — demonstrates registry components
  depending on other registry components.

---

## Suggested build order for Claude Code
1. `inlay-button` (high demand, teaches ripple/Core Animation).
2. `search-bar`, `home-tab-bar` (focus + indicator animations).
3. `horizontal-scroller`, `vertical-list` (collection-view foundations).
4. `splash-screen` (stroke-draw animation).
5. `settings-screen` (composite, depends on `vertical-list`).

Each new component: write the `.swift` + a `manifest.json` (schema in `CLAUDE.md`),
add it to the demo app, and verify it builds and animates in the Simulator before
marking it done.




//
//  PagedImageView.swift
//  Inlay — component
//
//  A swipeable image carousel: one image fills the container, swipe horizontally
//  to page through the rest, with page dots centered at the bottom showing the
//  current image. Tapping the dots jumps pages.
//
//      let carousel = PagedImageView(images: [img1, img2, img3, img4])
//      carousel.onPageChange = { index in print("now showing", index) }
//      view.addSubview(carousel)
//      // give it a frame / constraints — it fills whatever size you give it.
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class PagedImageView: UIView {

    // MARK: - Configuration

    struct Configuration {
        var cornerRadius: CGFloat = 16
        var imageContentMode: UIView.ContentMode = .scaleAspectFill
        var activeDotColor: UIColor = .label
        var inactiveDotColor: UIColor = .quaternaryLabel
        var showsPageControl: Bool = true
        /// Spring used for programmatic page jumps.
        var animation: Inlay.Spring = .snappy
        static let `default` = Configuration()
    }

    // MARK: - Public

    /// Called whenever the visible page changes (by swipe or tap).
    var onPageChange: ((Int) -> Void)?
    private(set) var currentPage = 0

    // MARK: - Private

    private let configuration: Configuration
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let pageControl = UIPageControl()
    private var imageViews: [UIImageView] = []

    // MARK: - Init

    init(images: [UIImage?] = [], configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
        setImages(images)
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = configuration.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentStack.axis = .horizontal
        contentStack.distribution = .fillEqually
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        pageControl.currentPageIndicatorTintColor = configuration.activeDotColor
        pageControl.pageIndicatorTintColor = configuration.inactiveDotColor
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        addSubview(pageControl)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Content

    func setImages(_ images: [UIImage?]) {
        for view in imageViews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        imageViews.removeAll()

        for image in images {
            let imageView = UIImageView(image: image)
            imageView.contentMode = configuration.imageContentMode
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ).isActive = true
            contentStack.addArrangedSubview(imageView)
            imageViews.append(imageView)
        }

        pageControl.numberOfPages = images.count
        pageControl.isHidden = !configuration.showsPageControl || images.count <= 1
        currentPage = 0
        pageControl.currentPage = 0
    }

    // MARK: - Paging

    func scrollToPage(_ page: Int, animated: Bool = true) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        scrollView.setContentOffset(CGPoint(x: CGFloat(page) * width, y: 0), animated: animated)
    }

    @objc private func pageControlChanged() {
        scrollToPage(pageControl.currentPage, animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension PagedImageView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / width).rounded())
        guard page != currentPage else { return }
        currentPage = page
        pageControl.currentPage = page
        onPageChange?(page)
    }
}





//
//  RevealView.swift
//  Inlay — component
//
//  A shape (rounded rectangle or circle) that springs open from the center,
//  scaling from 0% to 100%. Use it for reveal animations, success badges,
//  expanding panels, attention pulses, etc. Handles both the "box grows from
//  center" and "circle grows from center" cases via `Configuration.shape`.
//
//      let box = RevealView()                 // reveals automatically on appear
//      let circle = RevealView(configuration: {
//          var c = RevealView.Configuration.default
//          c.shape = .circle
//          c.fillColor = .systemGreen
//          return c
//      }())
//      // trigger manually:  box.reveal()  /  box.conceal()  /  box.toggle()
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class RevealView: UIView {

    // MARK: - Configuration

    struct Configuration {
        var shape: Shape = .roundedRect(cornerRadius: 20)
        var fillColor: UIColor = .tintColor
        var animation: Inlay.Spring = .playful
        /// Near-zero so the start matrix stays invertible (avoids transform warnings).
        var collapsedScale: CGFloat = 0.01
        /// Reveal automatically the first time the view appears.
        var revealsOnAppear: Bool = true

        enum Shape {
            case roundedRect(cornerRadius: CGFloat)
            case circle
        }
        static let `default` = Configuration()
    }

    // MARK: - Private

    private let configuration: Configuration
    private let shapeView = UIView()
    private var isRevealed = false
    private var hasAutoRevealed = false

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Public

    /// Optional content centered inside the shape (a checkmark, label, icon…).
    func setContent(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        shapeView.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: shapeView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: shapeView.centerYAnchor),
        ])
    }

    func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.shapeView.transform = .identity
        }
    }

    func conceal() {
        guard isRevealed else { return }
        isRevealed = false
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.shapeView.transform = self.collapsedTransform
        }
    }

    func toggle() { isRevealed ? conceal() : reveal() }

    // MARK: - Setup

    private var collapsedTransform: CGAffineTransform {
        CGAffineTransform(scaleX: configuration.collapsedScale, y: configuration.collapsedScale)
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        shapeView.backgroundColor = configuration.fillColor
        shapeView.layer.cornerCurve = .continuous
        shapeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shapeView)
        NSLayoutConstraint.activate([
            shapeView.topAnchor.constraint(equalTo: topAnchor),
            shapeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            shapeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            shapeView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Transforms scale from the view's center by default — exactly what we want.
        shapeView.transform = collapsedTransform
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch configuration.shape {
        case .roundedRect(let radius):
            shapeView.layer.cornerRadius = radius
        case .circle:
            shapeView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, configuration.revealsOnAppear, !hasAutoRevealed else { return }
        hasAutoRevealed = true
        DispatchQueue.main.async { [weak self] in self?.reveal() }
    }
}




//
//  BouncingLoader.swift
//  Inlay — component
//
//  A playful loading / buffering indicator: a row of small dots with a slightly
//  larger ball bouncing above them. Starts automatically when shown and pauses
//  when removed from the screen.
//
//      let loader = BouncingLoader()
//      view.addSubview(loader)
//      loader.centerInSuperview()      // or your own constraints
//      // loader.startAnimating() / loader.stopAnimating() to control manually
//
//  No registry dependencies — pure UIKit.
//

import UIKit

final class BouncingLoader: UIView {

    // MARK: - Configuration

    struct Configuration {
        var dotCount: Int = 3
        var dotSize: CGFloat = 8
        var dotSpacing: CGFloat = 10
        var dotColor: UIColor = .quaternaryLabel
        var ballSize: CGFloat = 12
        var ballColor: UIColor = .tintColor
        var bounceHeight: CGFloat = 18
        var bounceDuration: TimeInterval = 0.45
        var autoStarts: Bool = true
        static let `default` = Configuration()
    }

    // MARK: - Private

    private let configuration: Configuration
    private let dotsStack = UIStackView()
    private let ball = UIView()
    private var isAnimating = false

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        dotsStack.axis = .horizontal
        dotsStack.alignment = .center
        dotsStack.spacing = configuration.dotSpacing
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotsStack)

        for _ in 0 ..< max(1, configuration.dotCount) {
            let dot = UIView()
            dot.backgroundColor = configuration.dotColor
            dot.layer.cornerRadius = configuration.dotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: configuration.dotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: configuration.dotSize).isActive = true
            dotsStack.addArrangedSubview(dot)
        }

        ball.backgroundColor = configuration.ballColor
        ball.layer.cornerRadius = configuration.ballSize / 2
        ball.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ball)

        NSLayoutConstraint.activate([
            dotsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotsStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            ball.widthAnchor.constraint(equalToConstant: configuration.ballSize),
            ball.heightAnchor.constraint(equalToConstant: configuration.ballSize),
            ball.centerXAnchor.constraint(equalTo: centerXAnchor),
            ball.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -4),

            heightAnchor.constraint(
                greaterThanOrEqualToConstant:
                    configuration.ballSize + configuration.bounceHeight + configuration.dotSize + 8
            ),
        ])
    }

    // MARK: - Control

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        ball.transform = .identity
        UIView.animate(
            withDuration: configuration.bounceDuration,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseOut],
            animations: {
                self.ball.transform = CGAffineTransform(
                    translationX: 0, y: -self.configuration.bounceHeight
                )
            }
        )
    }

    func stopAnimating() {
        isAnimating = false
        ball.layer.removeAllAnimations()
        ball.transform = .identity
    }

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if configuration.autoStarts { startAnimating() }
        } else {
            // Pause off-screen so we don't burn cycles; allow restart later.
            isAnimating = false
            ball.layer.removeAllAnimations()
        }
    }
}