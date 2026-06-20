//
//  FloatingToolbar.swift
//  Inlay — component
//
//  A floating, pill-shaped toolbar with a glass (blur) or solid background,
//  a spring entrance animation, tactile press feedback, and an optional
//  selection highlight.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `FloatingToolbar.Configuration`.
//
//      let toolbar = FloatingToolbar(items: [
//          .init(icon: UIImage(systemName: "house.fill"))     { print("home") },
//          .init(icon: UIImage(systemName: "magnifyingglass")) { print("search") },
//          .init(icon: UIImage(systemName: "bell.fill"))       { print("alerts") },
//          .init(icon: UIImage(systemName: "person.fill"))     { print("profile") },
//      ])
//      view.addSubview(toolbar)
//      NSLayoutConstraint.activate([
//          toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          toolbar.bottomAnchor.constraint(
//              equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class FloatingToolbar: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Tint for item icons and the selection highlight.
        var accentColor: UIColor = .tintColor
        /// Background appearance.
        var background: Background = .glass(.systemThinMaterial)
        /// Corner radius of the pill. Large values read as fully rounded.
        var cornerRadius: CGFloat = 28
        /// Horizontal padding inside the bar.
        var horizontalInset: CGFloat = 16
        /// Spacing between items.
        var itemSpacing: CGFloat = 8
        /// Tappable size of each item.
        var itemSize: CGFloat = 44
        /// Spring used for entrance + press feedback. (Shared design token.)
        var animation: Inlay.Spring = .lively
        /// Whether a highlight follows the last-tapped item.
        var showsSelection: Bool = true
        /// Haptic feedback on tap.
        var hapticsEnabled: Bool = true

        enum Background {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
        }

        static let `default` = Configuration()
    }

    // MARK: - Item

    /// A single tappable item. Provide an SF Symbol (or any image) and a
    /// closure to run on tap.
    struct Item {
        let icon: UIImage?
        let title: String?
        let onTap: () -> Void

        init(icon: UIImage?, title: String? = nil, onTap: @escaping () -> Void) {
            self.icon = icon
            self.title = title
            self.onTap = onTap
        }
    }

    // MARK: - Private state

    private let configuration: Configuration
    private var items: [Item]
    private let container = UIView()
    private let stack = UIStackView()
    private var backgroundView = UIView()
    private var selectionView: UIView?
    private var buttons: [UIButton] = []
    private var hasAppeared = false

    // MARK: - Init

    init(items: [Item], configuration: Configuration = .default) {
        self.configuration = configuration
        self.items = items
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.items = []
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // Outer view carries the shadow and must NOT clip.
        setUpShadow()

        // Inner container clips the corner radius + background.
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = configuration.cornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setUpBackground()
        setUpStack()
        rebuildItems()
        prepareForEntrance()
    }

    private func setUpShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    private func setUpBackground() {
        switch configuration.background {
        case .glass(let style):
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .solid(let color):
            let view = UIView()
            view.backgroundColor = color
            backgroundView = view
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        container.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func setUpStack() {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = configuration.itemSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 8,
            left: configuration.horizontalInset,
            bottom: 8,
            right: configuration.horizontalInset
        )
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    // MARK: - Items

    /// Replace the toolbar's items at runtime.
    func setItems(_ items: [Item]) {
        self.items = items
        rebuildItems()
    }

    private func rebuildItems() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons.removeAll()

        for (index, item) in items.enumerated() {
            let button = makeButton(for: item, at: index)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    private func makeButton(for item: Item, at index: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = item.icon
        config.title = item.title
        config.baseForegroundColor = configuration.accentColor
        config.imagePlacement = .top
        config.imagePadding = 2

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: configuration.itemSize).isActive = true
        button.widthAnchor.constraint(
            greaterThanOrEqualToConstant: configuration.itemSize
        ).isActive = true

        button.addAction(UIAction { [weak self] _ in
            self?.handleTap(at: index, button: button, item: item)
        }, for: .touchUpInside)

        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(buttonTouchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return button
    }

    // MARK: - Interaction

    private func handleTap(at index: Int, button: UIButton, item: Item) {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if configuration.showsSelection {
            moveSelection(to: button)
        }
        item.onTap()
    }

    @objc private func buttonTouchDown(_ sender: UIButton) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }

    @objc private func buttonTouchUp(_ sender: UIButton) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = .identity
        }
    }

    private func moveSelection(to button: UIButton) {
        let pill: UIView
        if let existing = selectionView {
            pill = existing
        } else {
            let view = UIView()
            view.backgroundColor = configuration.accentColor.withAlphaComponent(0.18)
            view.layer.cornerRadius = configuration.itemSize / 2
            view.layer.cornerCurve = .continuous
            view.isUserInteractionEnabled = false
            container.insertSubview(view, belowSubview: stack)
            selectionView = view
            pill = view
        }
        container.layoutIfNeeded()
        let target = button.convert(button.bounds, to: container)
        Inlay.SpringAnimator.animate(configuration.animation) {
            pill.frame = target
        }
    }

    // MARK: - Entrance animation

    private func prepareForEntrance() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
    }

    /// Plays the entrance once. Called automatically when added to a window,
    /// but safe to call manually.
    func playEntrance() {
        guard !hasAppeared else { return }
        hasAppeared = true
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.playEntrance() }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the pill shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }
}
