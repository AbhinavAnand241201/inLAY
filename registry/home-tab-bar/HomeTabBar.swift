//
//  HomeTabBar.swift
//  Inlay — component
//
//  A custom bottom tab bar for 3, 4, or 5 tabs (the count equals the number of
//  items you pass). Selecting a tab springs its icon up, tints it with the
//  accent color, and slides an indicator (pill / underline / dot) between tabs.
//  It only emits the selected index — your host swaps the content.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `HomeTabBar.Configuration`.
//
//      let tabBar = HomeTabBar(items: [
//          .init(icon: UIImage(systemName: "house"),
//                selectedIcon: UIImage(systemName: "house.fill"),
//                title: "Home") { print("home") },
//          .init(icon: UIImage(systemName: "magnifyingglass"),
//                title: "Search") { print("search") },
//          .init(icon: UIImage(systemName: "person"),
//                selectedIcon: UIImage(systemName: "person.fill"),
//                title: "Profile") { print("profile") },
//      ])
//      tabBar.onChange = { index in print("selected", index) }
//      view.addSubview(tabBar)
//      NSLayoutConstraint.activate([
//          tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
//          tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
//          tabBar.bottomAnchor.constraint(
//              equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class HomeTabBar: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Whether items show titles beneath their icons.
        var style: Style = .icons
        /// Shape of the sliding indicator behind the selected tab.
        var indicator: Indicator = .pill
        /// Background appearance of the bar.
        var background: Background = .glass(.systemThinMaterial)
        /// Tint applied to the selected icon, title, and indicator.
        var accentColor: UIColor = .tintColor
        /// Tint applied to unselected items.
        var inactiveColor: UIColor = .secondaryLabel
        /// Corner radius of the bar. Large values read as fully rounded.
        var cornerRadius: CGFloat = 28
        /// Height of each tab (the bar's content height).
        var itemHeight: CGFloat = 56
        /// Horizontal padding inside the bar.
        var horizontalInset: CGFloat = 8
        /// Spring used for selection + indicator motion. (Shared design token.)
        var animation: Inlay.Spring = .lively
        /// Haptic feedback on selection.
        var hapticsEnabled: Bool = true

        enum Style {
            case icons
            case iconsAndTitles
        }

        enum Indicator {
            case pill
            case underline
            case dot
        }

        enum Background {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
        }

        static let `default` = Configuration()
    }

    // MARK: - Item

    /// A single tab. Provide an SF Symbol (or any image), an optional selected
    /// variant, an optional title, and a closure to run when selected.
    struct Item {
        let icon: UIImage?
        let selectedIcon: UIImage?
        let title: String?
        let onSelect: () -> Void

        init(
            icon: UIImage?,
            selectedIcon: UIImage? = nil,
            title: String? = nil,
            onSelect: @escaping () -> Void
        ) {
            self.icon = icon
            self.selectedIcon = selectedIcon
            self.title = title
            self.onSelect = onSelect
        }
    }

    // MARK: - Public API

    /// The currently selected tab. Setting it animates the indicator + icon.
    var selectedIndex: Int {
        get { _selectedIndex }
        set { select(newValue, animated: true, notify: false) }
    }

    /// Called whenever the selection changes (including programmatic changes).
    var onChange: ((Int) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private var items: [Item]
    private let container = UIView()
    private let stack = UIStackView()
    private var backgroundView = UIView()
    private let indicatorView = UIView()
    private var buttons: [TabButton] = []
    private var _selectedIndex = 0
    private var hasLaidOutIndicator = false

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
        setUpIndicator()
        setUpStack()
        rebuildItems()
        applySelectionAppearance(animated: false)
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

    private func setUpIndicator() {
        // Placed behind the buttons; moved by animating its frame after layout.
        indicatorView.isUserInteractionEnabled = false
        indicatorView.layer.cornerCurve = .continuous
        switch configuration.indicator {
        case .pill:
            indicatorView.backgroundColor = configuration.accentColor.withAlphaComponent(0.18)
        case .underline, .dot:
            indicatorView.backgroundColor = configuration.accentColor
        }
        container.addSubview(indicatorView)
    }

    private func setUpStack() {
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 0,
            left: configuration.horizontalInset,
            bottom: 0,
            right: configuration.horizontalInset
        )
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: configuration.itemHeight),
        ])
    }

    // MARK: - Items

    /// Replace the bar's items at runtime.
    func setItems(_ items: [Item]) {
        self.items = items
        if _selectedIndex >= items.count { _selectedIndex = 0 }
        rebuildItems()
        applySelectionAppearance(animated: false)
        hasLaidOutIndicator = false
        setNeedsLayout()
    }

    private func rebuildItems() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttons.removeAll()

        let showsTitle = configuration.style == .iconsAndTitles
        for (index, item) in items.enumerated() {
            let button = TabButton(item: item, showsTitle: showsTitle)
            button.addAction(UIAction { [weak self] _ in
                self?.handleTap(at: index)
            }, for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    // MARK: - Interaction

    private func handleTap(at index: Int) {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        select(index, animated: true, notify: true)
        items[index].onSelect()
    }

    private func select(_ index: Int, animated: Bool, notify: Bool) {
        guard index >= 0, index < items.count, index != _selectedIndex else {
            if notify, index == _selectedIndex { onChange?(index) }
            return
        }
        _selectedIndex = index
        applySelectionAppearance(animated: animated)
        moveIndicator(animated: animated)
        onChange?(index)
    }

    private func applySelectionAppearance(animated: Bool) {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == _selectedIndex
            let color = isSelected ? configuration.accentColor : configuration.inactiveColor
            let apply = {
                button.setSelected(isSelected, color: color)
            }
            if animated {
                Inlay.SpringAnimator.animate(configuration.animation, apply)
            } else {
                apply()
            }
        }
    }

    // MARK: - Indicator

    private func moveIndicator(animated: Bool) {
        guard _selectedIndex < buttons.count else { return }
        container.layoutIfNeeded()
        let target = indicatorFrame(for: buttons[_selectedIndex])
        let apply = { self.indicatorView.frame = target }
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, apply)
        } else {
            apply()
        }
        switch configuration.indicator {
        case .pill:
            indicatorView.layer.cornerRadius = min(target.height, target.width) / 2
        case .underline:
            indicatorView.layer.cornerRadius = target.height / 2
        case .dot:
            indicatorView.layer.cornerRadius = target.height / 2
        }
    }

    private func indicatorFrame(for button: TabButton) -> CGRect {
        let cell = button.convert(button.bounds, to: container)
        switch configuration.indicator {
        case .pill:
            let inset: CGFloat = 6
            return cell.insetBy(dx: inset, dy: inset)
        case .underline:
            let width = min(cell.width * 0.5, 28)
            let height: CGFloat = 3
            return CGRect(
                x: cell.midX - width / 2,
                y: cell.maxY - height - 6,
                width: width,
                height: height
            )
        case .dot:
            let size: CGFloat = 5
            return CGRect(
                x: cell.midX - size / 2,
                y: cell.maxY - size - 7,
                width: size,
                height: size
            )
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the bar shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath

        // Position the indicator once geometry is known (and keep it tracking
        // on rotation / resize), without animating the very first placement.
        if !hasLaidOutIndicator, !buttons.isEmpty {
            hasLaidOutIndicator = true
            moveIndicator(animated: false)
        }
    }

    // MARK: - TabButton

    /// One tappable tab. Nested so it can never collide with another
    /// component's helper types.
    private final class TabButton: UIButton {
        private let iconView = UIImageView()
        private let label = UILabel()
        private let item: Item
        private let showsTitle: Bool

        init(item: Item, showsTitle: Bool) {
            self.item = item
            self.showsTitle = showsTitle
            super.init(frame: .zero)
            setUp()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setUp() {
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.isUserInteractionEnabled = false
            iconView.image = item.icon
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: 20,
                weight: .semibold
            )

            label.translatesAutoresizingMaskIntoConstraints = false
            label.isUserInteractionEnabled = false
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.text = item.title
            label.isHidden = !(showsTitle && item.title != nil)

            let group = UIStackView(arrangedSubviews: [iconView, label])
            group.axis = .vertical
            group.alignment = .center
            group.spacing = 2
            group.translatesAutoresizingMaskIntoConstraints = false
            group.isUserInteractionEnabled = false
            addSubview(group)

            NSLayoutConstraint.activate([
                group.centerXAnchor.constraint(equalTo: centerXAnchor),
                group.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.heightAnchor.constraint(equalToConstant: 24),
                iconView.widthAnchor.constraint(equalToConstant: 24),
            ])
        }

        func setSelected(_ isSelected: Bool, color: UIColor) {
            iconView.image = isSelected ? (item.selectedIcon ?? item.icon) : item.icon
            iconView.tintColor = color
            label.textColor = color
            // Lift the selected icon slightly for a tactile "pop".
            let lift: CGFloat = isSelected ? -3 : 0
            iconView.transform = CGAffineTransform(translationX: 0, y: lift)
        }
    }
}
