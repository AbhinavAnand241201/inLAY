//
//  SpeedDialButton.swift
//  Inlay — component
//
//  A floating action button (FAB) that expands into a fan of mini action
//  buttons with a staggered spring, optional labels that slide + fade in
//  beside each action, a rotating main icon (e.g. plus → ×), and an optional
//  dimmed backdrop. Tapping an action or the backdrop collapses it.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SpeedDialButton.Configuration`.
//
//      let fab = SpeedDialButton(
//          mainIcon: UIImage(systemName: "plus"),
//          actions: [
//              .init(icon: UIImage(systemName: "camera.fill"), title: "Photo") { print("photo") },
//              .init(icon: UIImage(systemName: "mic.fill"),    title: "Audio") { print("audio") },
//              .init(icon: UIImage(systemName: "doc.fill"),    title: "File")  { print("file") },
//          ]
//      )
//      view.addSubview(fab)
//      NSLayoutConstraint.activate([
//          fab.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
//          fab.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SpeedDialButton: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Direction the action buttons fan out from the FAB.
        var expandDirection: Direction = .up
        /// Fill color of the main FAB.
        var mainColor: UIColor = .tintColor
        /// Tint of the main FAB's icon.
        var mainIconColor: UIColor = .white
        /// Fill color of each action button.
        var actionColor: UIColor = .secondarySystemBackground
        /// Tint of each action button's icon.
        var actionIconColor: UIColor = .label
        /// Diameter of the main FAB.
        var mainSize: CGFloat = 56
        /// Diameter of each action button.
        var actionSize: CGFloat = 46
        /// Gap between successive buttons along the expand axis.
        var spacing: CGFloat = 14
        /// Whether labels appear beside actions (requires `Action.title`).
        var showsLabels: Bool = true
        /// Background of the label chip.
        var labelBackground: UIColor = .systemBackground
        /// Text color of the label chip.
        var labelTextColor: UIColor = .label
        /// Whether a dimmed backdrop appears behind the expanded actions.
        var backdropDim: Bool = true
        /// Color of the backdrop dim.
        var backdropColor: UIColor = .black
        /// Peak alpha of the backdrop when fully expanded.
        var backdropAlpha: CGFloat = 0.28
        /// Degrees the main icon rotates on expand (e.g. 45 → plus to ×).
        var rotatesMainIconOnExpand: CGFloat = 45
        /// Spring used for every transition. (Shared design token.)
        var animation: Inlay.Spring = .playful
        /// Per-item delay so actions cascade out instead of moving in unison.
        var staggerDelay: TimeInterval = 0.04
        /// Light haptic on expand/collapse and action tap.
        var hapticsEnabled: Bool = true

        /// Direction the actions fan out from the FAB.
        enum Direction {
            case up, down, left, right

            /// Unit offset applied per step along the expand axis.
            var unitOffset: CGPoint {
                switch self {
                case .up:    return CGPoint(x: 0, y: -1)
                case .down:  return CGPoint(x: 0, y: 1)
                case .left:  return CGPoint(x: -1, y: 0)
                case .right: return CGPoint(x: 1, y: 0)
                }
            }

            /// Whether the axis is vertical (labels sit horizontally beside the action).
            var isVertical: Bool { self == .up || self == .down }
        }

        static let `default` = Configuration()
    }

    // MARK: - Action

    /// A single mini action revealed on expand. Provide an SF Symbol (or any
    /// image), an optional label, and a closure to run on tap.
    struct Action {
        let icon: UIImage?
        let title: String?
        let onTap: () -> Void

        init(icon: UIImage?, title: String? = nil, onTap: @escaping () -> Void) {
            self.icon = icon
            self.title = title
            self.onTap = onTap
        }
    }

    // MARK: - Public state

    /// Expanded state. Setting it animates the transition.
    var isExpanded: Bool {
        get { _isExpanded }
        set {
            guard newValue != _isExpanded else { return }
            _isExpanded = newValue
            applyExpanded(newValue, animated: true)
        }
    }

    /// Toggle expansion, optionally without animation.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != _isExpanded else { return }
        _isExpanded = expanded
        applyExpanded(expanded, animated: animated)
    }

    // MARK: - Private state

    private let configuration: Configuration
    private let actions: [Action]
    private let mainIcon: UIImage?

    private let mainButton = UIButton(type: .custom)
    private let backdrop = UIView()
    private var actionViews: [ActionView] = []
    private var _isExpanded = false

    // MARK: - Init

    init(mainIcon: UIImage?, actions: [Action], configuration: Configuration = .default) {
        self.configuration = configuration
        self.actions = actions
        self.mainIcon = mainIcon
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.actions = []
        self.mainIcon = nil
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        // Actions extend beyond the FAB bounds, so never clip.
        clipsToBounds = false

        // Self sizes to the main FAB.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: configuration.mainSize),
            heightAnchor.constraint(equalToConstant: configuration.mainSize),
        ])

        setUpBackdrop()
        setUpActions()
        setUpMainButton()
    }

    private func setUpBackdrop() {
        backdrop.backgroundColor = configuration.backdropColor
        backdrop.alpha = 0
        backdrop.isUserInteractionEnabled = false
        backdrop.isHidden = !configuration.backdropDim
        addSubview(backdrop)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        backdrop.addGestureRecognizer(tap)
    }

    private func setUpActions() {
        for action in actions {
            let view = ActionView(
                action: action,
                configuration: configuration
            )
            view.onTap = { [weak self] in self?.handleActionTap(action) }
            // Added above the backdrop, below the main button (added last).
            addSubview(view)
            actionViews.append(view)
            // Start collapsed: centered on the FAB, hidden.
            view.frame = collapsedFrame(for: view)
            view.alpha = 0
            view.isUserInteractionEnabled = false
        }
    }

    private func setUpMainButton() {
        mainButton.translatesAutoresizingMaskIntoConstraints = false
        mainButton.backgroundColor = configuration.mainColor
        mainButton.tintColor = configuration.mainIconColor
        mainButton.setImage(
            mainIcon?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        mainButton.layer.cornerRadius = configuration.mainSize / 2
        mainButton.layer.cornerCurve = .continuous

        // Shadow on the FAB; the button itself does not clip.
        mainButton.layer.shadowColor = UIColor.black.cgColor
        mainButton.layer.shadowOpacity = 0.25
        mainButton.layer.shadowRadius = 12
        mainButton.layer.shadowOffset = CGSize(width: 0, height: 6)

        mainButton.addTarget(self, action: #selector(mainTouchDown), for: .touchDown)
        mainButton.addTarget(
            self,
            action: #selector(mainTouchUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        mainButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)

        addSubview(mainButton)
        NSLayoutConstraint.activate([
            mainButton.topAnchor.constraint(equalTo: topAnchor),
            mainButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Hit testing (actions live outside our bounds)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        // When expanded, the backdrop + action views extend past our bounds.
        for subview in subviews where !subview.isHidden && subview.alpha > 0.01 {
            let converted = convert(point, to: subview)
            if subview.point(inside: converted, with: event) { return true }
        }
        return false
    }

    // MARK: - Geometry

    /// Frame for an action when collapsed: centered behind the FAB.
    private func collapsedFrame(for view: ActionView) -> CGRect {
        let size = view.intrinsicContentSize
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Frame for an action when expanded at the given index.
    private func expandedFrame(for view: ActionView, at index: Int) -> CGRect {
        let size = view.intrinsicContentSize
        let unit = configuration.expandDirection.unitOffset
        let step = configuration.actionSize + configuration.spacing
        let distance = configuration.mainSize / 2
            + configuration.spacing
            + configuration.actionSize / 2
            + CGFloat(index) * step

        // Anchor on the action *button* center (not the whole chip), so the
        // dots align in a straight line regardless of label width.
        let fabCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let buttonCenter = CGPoint(
            x: fabCenter.x + unit.x * distance,
            y: fabCenter.y + unit.y * distance
        )

        // Position the chip so its action-button portion centers on buttonCenter.
        let buttonHalf = configuration.actionSize / 2
        var origin: CGPoint
        switch configuration.expandDirection {
        case .up, .down:
            // Button is horizontally centered in the chip.
            origin = CGPoint(
                x: buttonCenter.x - size.width / 2,
                y: buttonCenter.y - buttonHalf
            )
        case .right:
            // Action button sits at the leading edge of the chip.
            origin = CGPoint(
                x: buttonCenter.x - buttonHalf,
                y: buttonCenter.y - size.height / 2
            )
        case .left:
            // Action button sits at the trailing edge of the chip.
            origin = CGPoint(
                x: buttonCenter.x + buttonHalf - size.width,
                y: buttonCenter.y - size.height / 2
            )
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Interaction

    @objc private func toggle() {
        isExpanded.toggle()
    }

    @objc private func handleBackdropTap() {
        isExpanded = false
    }

    private func handleActionTap(_ action: Action) {
        fireHaptic()
        action.onTap()
        isExpanded = false
    }

    @objc private func mainTouchDown() {
        Inlay.SpringAnimator.animate(.snappy) {
            self.mainButton.transform = self.mainButton.transform
                .scaledBy(x: 0.9, y: 0.9)
        }
    }

    @objc private func mainTouchUp() {
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.mainButton.transform = self.rotationTransform(for: self.isExpanded)
        }
    }

    // MARK: - Expansion

    private func rotationTransform(for expanded: Bool) -> CGAffineTransform {
        guard expanded else { return .identity }
        let radians = configuration.rotatesMainIconOnExpand * .pi / 180
        return CGAffineTransform(rotationAngle: radians)
    }

    private func fireHaptic() {
        guard configuration.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        layoutIfNeeded()
        fireHaptic()

        if expanded {
            // Make sure action views start from the collapsed pose.
            for view in actionViews where view.alpha < 0.01 {
                view.frame = collapsedFrame(for: view)
            }
        }

        // Backdrop.
        if configuration.backdropDim {
            let targetAlpha = expanded ? configuration.backdropAlpha : 0
            let backdropBlock = { self.backdrop.alpha = targetAlpha }
            if animated {
                Inlay.SpringAnimator.animate(configuration.animation, backdropBlock)
            } else {
                backdropBlock()
            }
            backdrop.isUserInteractionEnabled = expanded
            if expanded { bringBackdropForward() }
        }

        // Main icon rotation.
        let rotationBlock = {
            self.mainButton.transform = self.rotationTransform(for: expanded)
        }
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, rotationBlock)
        } else {
            rotationBlock()
        }

        // Staggered actions. On collapse the order reverses so the closest
        // action retracts last.
        let count = actionViews.count
        for (index, view) in actionViews.enumerated() {
            view.isUserInteractionEnabled = expanded
            let staggerIndex = expanded ? index : (count - 1 - index)
            let delay = configuration.staggerDelay * Double(staggerIndex)

            let target = expanded
                ? expandedFrame(for: view, at: index)
                : collapsedFrame(for: view)
            let targetAlpha: CGFloat = expanded ? 1 : 0

            let animateBlock = {
                Inlay.SpringAnimator.animate(self.configuration.animation) {
                    view.frame = target
                    view.alpha = targetAlpha
                    view.setLabelRevealed(expanded)
                }
            }

            if animated {
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: animateBlock)
                } else {
                    animateBlock()
                }
            } else {
                view.frame = target
                view.alpha = targetAlpha
                view.setLabelRevealed(expanded)
            }
        }
    }

    /// Keep the backdrop directly under the actions + FAB.
    private func bringBackdropForward() {
        bringSubviewToFront(backdrop)
        for view in actionViews { bringSubviewToFront(view) }
        bringSubviewToFront(mainButton)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Expand the backdrop to cover the whole window so the dim reads.
        if let host = window {
            let frameInSelf = host.convert(host.bounds, to: self)
            backdrop.frame = frameInSelf
        }
        // Keep collapsed actions pinned under the FAB before first expand.
        if !isExpanded {
            for view in actionViews where view.alpha < 0.01 {
                view.frame = collapsedFrame(for: view)
            }
        }
        // FAB shadow path for crisp, performant shadows.
        mainButton.layer.shadowPath = UIBezierPath(
            ovalIn: mainButton.bounds
        ).cgPath
    }

    // MARK: - ActionView

    /// A single action: a circular button plus an optional sliding label chip.
    private final class ActionView: UIView {

        var onTap: (() -> Void)?

        private let configuration: Configuration
        private let button = UIButton(type: .custom)
        private let label = UILabel()
        private let labelChip = UIView()
        private let hasLabel: Bool
        private let isVertical: Bool

        // Label slides in from the FAB side; this is its hidden offset.
        private var labelHiddenTransform: CGAffineTransform = .identity

        init(action: Action, configuration: Configuration) {
            self.configuration = configuration
            self.isVertical = configuration.expandDirection.isVertical
            self.hasLabel = configuration.showsLabels
                && (action.title?.isEmpty == false)
                && !isVertical // labels render beside left/right axes cleanly
            super.init(frame: .zero)
            setUp(action: action)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private func setUp(action: Action) {
            isUserInteractionEnabled = true
            clipsToBounds = false

            // Circular button.
            button.frame = CGRect(
                x: 0, y: 0,
                width: configuration.actionSize,
                height: configuration.actionSize
            )
            button.backgroundColor = configuration.actionColor
            button.tintColor = configuration.actionIconColor
            button.setImage(
                action.icon?.withRenderingMode(.alwaysTemplate),
                for: .normal
            )
            button.layer.cornerRadius = configuration.actionSize / 2
            button.layer.cornerCurve = .continuous
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.18
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 3)
            button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            addSubview(button)

            if hasLabel {
                labelChip.backgroundColor = configuration.labelBackground
                labelChip.layer.cornerRadius = 8
                labelChip.layer.cornerCurve = .continuous
                labelChip.layer.shadowColor = UIColor.black.cgColor
                labelChip.layer.shadowOpacity = 0.15
                labelChip.layer.shadowRadius = 6
                labelChip.layer.shadowOffset = CGSize(width: 0, height: 2)
                labelChip.isUserInteractionEnabled = false

                label.text = action.title
                label.font = .preferredFont(forTextStyle: .subheadline)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = configuration.labelTextColor
                label.translatesAutoresizingMaskIntoConstraints = false

                labelChip.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: labelChip.leadingAnchor, constant: 10),
                    label.trailingAnchor.constraint(equalTo: labelChip.trailingAnchor, constant: -10),
                    label.topAnchor.constraint(equalTo: labelChip.topAnchor, constant: 6),
                    label.bottomAnchor.constraint(equalTo: labelChip.bottomAnchor, constant: -6),
                ])
                addSubview(labelChip)
            }

            layoutContents()
        }

        @objc private func tapped() { onTap?() }

        // MARK: Sizing

        private var labelSize: CGSize {
            guard hasLabel else { return .zero }
            label.sizeToFit()
            return CGSize(
                width: label.intrinsicContentSize.width + 20,
                height: max(configuration.actionSize, label.intrinsicContentSize.height + 12)
            )
        }

        override var intrinsicContentSize: CGSize {
            let action = configuration.actionSize
            guard hasLabel else { return CGSize(width: action, height: action) }
            let chip = labelSize
            let gap: CGFloat = 10
            // Button + gap + label, laid out along the horizontal axis.
            return CGSize(
                width: action + gap + chip.width,
                height: max(action, chip.height)
            )
        }

        private func layoutContents() {
            let total = intrinsicContentSize
            frame = CGRect(origin: frame.origin, size: total)

            let action = configuration.actionSize
            let gap: CGFloat = 10

            switch configuration.expandDirection {
            case .right:
                // Button leading, label trailing.
                button.frame = CGRect(
                    x: 0, y: (total.height - action) / 2,
                    width: action, height: action
                )
                if hasLabel {
                    let chip = labelSize
                    labelChip.frame = CGRect(
                        x: action + gap,
                        y: (total.height - chip.height) / 2,
                        width: chip.width, height: chip.height
                    )
                    labelHiddenTransform = CGAffineTransform(translationX: -12, y: 0)
                }
            case .left:
                // Label leading, button trailing.
                button.frame = CGRect(
                    x: total.width - action,
                    y: (total.height - action) / 2,
                    width: action, height: action
                )
                if hasLabel {
                    let chip = labelSize
                    labelChip.frame = CGRect(
                        x: 0,
                        y: (total.height - chip.height) / 2,
                        width: chip.width, height: chip.height
                    )
                    labelHiddenTransform = CGAffineTransform(translationX: 12, y: 0)
                }
            case .up, .down:
                // Vertical axes: just the button, centered.
                button.frame = CGRect(
                    x: (total.width - action) / 2,
                    y: (total.height - action) / 2,
                    width: action, height: action
                )
            }

            if hasLabel {
                labelChip.alpha = 0
                labelChip.transform = labelHiddenTransform
            }
        }

        /// Slide + fade the label as the action reveals/hides.
        func setLabelRevealed(_ revealed: Bool) {
            guard hasLabel else { return }
            labelChip.alpha = revealed ? 1 : 0
            labelChip.transform = revealed ? .identity : labelHiddenTransform
        }
    }
}
