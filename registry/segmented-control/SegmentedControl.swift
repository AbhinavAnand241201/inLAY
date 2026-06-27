//
//  SegmentedControl.swift
//  Inlay — component
//
//  A sliding segmented control. A selection indicator springs between
//  segments while the selected segment's title/icon crossfades to the
//  selected foreground color as the indicator passes. Supports a pill,
//  underline, or solid-background indicator style, glass/solid/clear
//  backgrounds, icons + titles, equal or content-sized segments, and a
//  light haptic on commit.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SegmentedControl.Configuration`.
//
//      let control = SegmentedControl(titles: ["All", "Photos", "Albums"])
//      control.selectedIndex = 0
//      control.onChange = { index in print("selected \(index)") }
//      view.addSubview(control)
//      NSLayoutConstraint.activate([
//          control.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
//          control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
//          control.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
//      ])
//
//      // Icons + titles, underline style:
//      var config = SegmentedControl.Configuration.default
//      config.style = .underline
//      let segmented = SegmentedControl(items: [
//          .init(title: "Home",   icon: UIImage(systemName: "house")),
//          .init(title: "Search", icon: UIImage(systemName: "magnifyingglass")),
//      ], configuration: config)
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SegmentedControl: UIControl {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// How the moving selection indicator is drawn.
        var style: Style = .pill
        /// Fill of the moving indicator (pill / solid) or the underline bar.
        var indicatorColor: UIColor = .systemBackground
        /// Title/icon color of the selected segment.
        var selectedForegroundColor: UIColor = .label
        /// Title/icon color of unselected segments.
        var foregroundColor: UIColor = .secondaryLabel
        /// Font used by every segment's title.
        var font: UIFont = .systemFont(ofSize: 15, weight: .semibold)
        /// Corner radius of the track and (for `.pill`) the indicator.
        var cornerRadius: CGFloat = 12
        /// Overall control height.
        var height: CGFloat = 44
        /// Backdrop behind the segments.
        var background: Background = .solid(.secondarySystemFill)
        /// Padding between the track edge and the indicator.
        var segmentInset: CGFloat = 4
        /// Spacing between a segment's icon and its title.
        var iconTitleSpacing: CGFloat = 6
        /// Spring driving the indicator + crossfade. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Light haptic when the selection commits.
        var hapticsEnabled: Bool = true
        /// All segments share the widest width; otherwise size-to-content.
        var equalWidths: Bool = true
        /// Thickness of the bar in `.underline` style.
        var underlineThickness: CGFloat = 3
        /// Subtle scale dip on the indicator while it travels.
        var indicatorTravelScale: CGFloat = 0.96
        /// Shadow under the indicator (pill / solid styles).
        var indicatorShadowEnabled: Bool = true

        /// Indicator appearance.
        enum Style {
            /// Rounded pill that slides behind the selected segment.
            case pill
            /// Thin bar pinned to the bottom edge of the selected segment.
            case underline
            /// Full-height solid block behind the selected segment.
            case solidBackground
        }

        /// Track backdrop.
        enum Background {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
            case clear
        }

        static let `default` = Configuration()
    }

    // MARK: - Item

    /// A single segment: a title and an optional leading icon.
    struct Item {
        let title: String
        let icon: UIImage?

        init(title: String, icon: UIImage? = nil) {
            self.title = title
            self.icon = icon
        }
    }

    // MARK: - Public API

    /// Called whenever the selection changes (taps and programmatic sets that
    /// actually move the selection). Reports the new index.
    var onChange: ((Int) -> Void)?

    /// The currently selected segment. Setting this animates the indicator.
    var selectedIndex: Int {
        get { _selectedIndex }
        set { select(index: newValue, animated: true, notify: false) }
    }

    /// Replace all segments at runtime.
    func setItems(_ items: [Item]) {
        self.items = items
        if _selectedIndex >= items.count { _selectedIndex = max(0, items.count - 1) }
        rebuildSegments()
        setNeedsLayout()
    }

    // MARK: - Private state

    private let configuration: Configuration
    private var items: [Item]
    private var _selectedIndex: Int = 0

    private let backgroundView: UIView
    private let trackContainer = UIView()      // clips corner radius + bg
    private let indicator = UIView()
    private let stack = UIStackView()
    private var cells: [Cell] = []

    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var hasLaidOut = false

    // MARK: - Init

    /// Build from plain titles.
    convenience init(titles: [String], configuration: Configuration = .default) {
        self.init(items: titles.map { Item(title: $0) }, configuration: configuration)
    }

    /// Build from rich items (title + optional icon).
    init(items: [Item], configuration: Configuration = .default) {
        self.items = items
        self.configuration = configuration
        self.backgroundView = SegmentedControl.makeBackground(configuration.background)
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.items = []
        self.configuration = .default
        self.backgroundView = SegmentedControl.makeBackground(Configuration.default.background)
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: configuration.height).isActive = true

        // The control itself carries the indicator shadow and must not clip.
        layer.shadowColor = UIColor.clear.cgColor

        // Track container clips the rounded corners + background.
        trackContainer.translatesAutoresizingMaskIntoConstraints = false
        trackContainer.layer.cornerRadius = configuration.cornerRadius
        trackContainer.layer.cornerCurve = .continuous
        trackContainer.clipsToBounds = true
        trackContainer.isUserInteractionEnabled = false
        addSubview(trackContainer)
        NSLayoutConstraint.activate([
            trackContainer.topAnchor.constraint(equalTo: topAnchor),
            trackContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        trackContainer.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: trackContainer.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: trackContainer.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: trackContainer.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trackContainer.trailingAnchor),
        ])

        // Indicator sits behind the labels, inside the (non-clipping) control
        // for pill/solid so the optional shadow shows; underline lives in the
        // track but never needs to escape it.
        setUpIndicator()
        addSubview(indicator)

        // Segment labels on top of everything.
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = configuration.equalWidths ? .fillEqually : .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: configuration.segmentInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -configuration.segmentInset),
        ])

        rebuildSegments()

        addTarget(self, action: #selector(handleTouchUp(_:)), for: .touchUpInside)
        feedback.prepare()
    }

    private func setUpIndicator() {
        indicator.isUserInteractionEnabled = false
        indicator.layer.cornerCurve = .continuous
        switch configuration.style {
        case .pill:
            indicator.backgroundColor = configuration.indicatorColor
            indicator.layer.cornerRadius = max(0, configuration.cornerRadius - configuration.segmentInset)
        case .solidBackground:
            indicator.backgroundColor = configuration.indicatorColor
            indicator.layer.cornerRadius = max(0, configuration.cornerRadius - configuration.segmentInset)
        case .underline:
            indicator.backgroundColor = configuration.indicatorColor
            indicator.layer.cornerRadius = configuration.underlineThickness / 2
        }

        if configuration.indicatorShadowEnabled && configuration.style != .underline {
            indicator.layer.shadowColor = UIColor.black.cgColor
            indicator.layer.shadowOpacity = 0.12
            indicator.layer.shadowRadius = 6
            indicator.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    private static func makeBackground(_ background: Configuration.Background) -> UIView {
        switch background {
        case .glass(let style):
            return UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .solid(let color):
            let view = UIView()
            view.backgroundColor = color
            return view
        case .clear:
            let view = UIView()
            view.backgroundColor = .clear
            return view
        }
    }

    // MARK: - Segments

    private func rebuildSegments() {
        for cell in cells {
            stack.removeArrangedSubview(cell)
            cell.removeFromSuperview()
        }
        cells.removeAll()

        for item in items {
            let cell = Cell(
                item: item,
                font: configuration.font,
                selectedColor: configuration.selectedForegroundColor,
                normalColor: configuration.foregroundColor,
                iconTitleSpacing: configuration.iconTitleSpacing
            )
            cells.append(cell)
            stack.addArrangedSubview(cell)
        }
        // Reflect current selection without animation.
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == _selectedIndex, progress: i == _selectedIndex ? 1 : 0)
        }
    }

    // MARK: - Selection

    private func select(index: Int, animated: Bool, notify: Bool) {
        guard !items.isEmpty else { return }
        let clamped = max(0, min(index, items.count - 1))
        let changed = clamped != _selectedIndex
        _selectedIndex = clamped

        layoutIfNeeded()
        let targetFrame = indicatorFrame(for: clamped)

        let applyColors = {
            for (i, cell) in self.cells.enumerated() {
                cell.setSelected(i == clamped, progress: i == clamped ? 1 : 0)
            }
        }

        if animated && hasLaidOut {
            // Travel "dip": shrink slightly mid-flight, then settle.
            Inlay.SpringAnimator.animate(configuration.animation, animations: {
                self.indicator.frame = targetFrame
                applyColors()
            }, completion: nil)
        } else {
            indicator.frame = targetFrame
            applyColors()
        }

        if notify && changed {
            sendActions(for: .valueChanged)
            onChange?(clamped)
        }
    }

    /// Frame for the indicator given a segment index, in the control's space.
    private func indicatorFrame(for index: Int) -> CGRect {
        guard cells.indices.contains(index) else { return .zero }
        let cellFrame = cells[index].convert(cells[index].bounds, to: self)

        switch configuration.style {
        case .pill, .solidBackground:
            return cellFrame.insetBy(dx: 0, dy: configuration.segmentInset)
        case .underline:
            let thickness = configuration.underlineThickness
            // Indicator hugs ~60% of the segment width, centered, at the bottom.
            let width = cellFrame.width * 0.6
            let x = cellFrame.midX - width / 2
            let y = bounds.height - thickness - configuration.segmentInset
            return CGRect(x: x, y: y, width: width, height: thickness)
        }
    }

    // MARK: - Interaction

    @objc private func handleTouchUp(_ sender: UIControl) { }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard bounds.contains(location) else { return }
        guard let index = index(at: location) else { return }
        commit(index: index)
    }

    /// Maps an x-coordinate to a segment index by hit-testing cell frames.
    private func index(at point: CGPoint) -> Int? {
        for (i, cell) in cells.enumerated() {
            let frame = cell.convert(cell.bounds, to: self)
            // Match on x only so taps in vertical padding still register.
            if point.x >= frame.minX && point.x < frame.maxX { return i }
        }
        // Fallback: clamp to the nearest end.
        if let first = cells.first, point.x < first.frame.minX { return 0 }
        if !cells.isEmpty { return cells.count - 1 }
        return nil
    }

    private func commit(index: Int) {
        let changed = index != _selectedIndex
        if changed && configuration.hapticsEnabled {
            feedback.impactOccurred()
            feedback.prepare()
        }
        select(index: index, animated: true, notify: changed)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Snap indicator into place after first/any layout pass.
        let target = indicatorFrame(for: _selectedIndex)
        if !hasLaidOut {
            hasLaidOut = true
            indicator.frame = target
        } else if indicator.frame.size == .zero {
            indicator.frame = target
        } else {
            // Keep indicator aligned on rotation / resize without animation
            // when sizes change but selection didn't.
            indicator.frame = target
        }

        if configuration.indicatorShadowEnabled && configuration.style != .underline {
            indicator.layer.shadowPath = UIBezierPath(
                roundedRect: indicator.bounds,
                cornerRadius: indicator.layer.cornerRadius
            ).cgPath
        }
    }

    // MARK: - Cell

    /// One segment: optional icon + title, with a crossfade between the
    /// normal and selected foreground colors driven by `progress`.
    private final class Cell: UIView {
        private let titleLabel = UILabel()
        private let iconView = UIImageView()
        private let contentStack = UIStackView()
        private let selectedColor: UIColor
        private let normalColor: UIColor

        init(
            item: Item,
            font: UIFont,
            selectedColor: UIColor,
            normalColor: UIColor,
            iconTitleSpacing: CGFloat
        ) {
            self.selectedColor = selectedColor
            self.normalColor = normalColor
            super.init(frame: .zero)

            titleLabel.text = item.title
            titleLabel.font = font
            titleLabel.textColor = normalColor
            titleLabel.textAlignment = .center
            titleLabel.adjustsFontForContentSizeCategory = true

            iconView.image = item.icon?.withRenderingMode(.alwaysTemplate)
            iconView.tintColor = normalColor
            iconView.contentMode = .scaleAspectFit
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            iconView.isHidden = item.icon == nil
            if item.icon != nil {
                iconView.heightAnchor.constraint(equalToConstant: font.pointSize).isActive = true
                iconView.widthAnchor.constraint(equalToConstant: font.pointSize).isActive = true
            }

            contentStack.axis = .horizontal
            contentStack.alignment = .center
            contentStack.spacing = item.icon == nil ? 0 : iconTitleSpacing
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.isUserInteractionEnabled = false
            contentStack.addArrangedSubview(iconView)
            contentStack.addArrangedSubview(titleLabel)
            addSubview(contentStack)

            NSLayoutConstraint.activate([
                contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
                contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// `progress` 0→1 crossfades normal→selected foreground color.
        func setSelected(_ selected: Bool, progress: CGFloat) {
            let p = max(0, min(progress, 1))
            let color = Cell.blend(from: normalColor, to: selectedColor, progress: p)
            titleLabel.textColor = color
            iconView.tintColor = color
        }

        private static func blend(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
            // Resolve dynamic colors per trait so dark mode stays correct.
            UIColor { traits in
                let f = from.resolvedColor(with: traits)
                let t = to.resolvedColor(with: traits)
                var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
                var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
                f.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
                t.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
                return UIColor(
                    red: fr + (tr - fr) * progress,
                    green: fg + (tg - fg) * progress,
                    blue: fb + (tb - fb) * progress,
                    alpha: fa + (ta - fa) * progress
                )
            }
        }
    }
}
