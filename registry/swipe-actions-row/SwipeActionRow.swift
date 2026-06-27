//
//  SwipeActionRow.swift
//  Inlay — component
//
//  A swipe-to-reveal action row. Wraps any content view; dragging it
//  horizontally uncovers colored action buttons pinned to the leading
//  and/or trailing edge. Buttons grow with the drag, the row snaps open
//  or closed with a spring, and a FULL-SWIPE past a threshold triggers
//  the first action directly — sliding the content all the way across.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SwipeActionRow.Configuration`.
//
//      let label = UILabel()
//      label.text = "  Swipe me"
//      label.backgroundColor = .secondarySystemGroupedBackground
//
//      let row = SwipeActionRow(
//          contentView: label,
//          trailingActions: [
//              .init(icon: UIImage(systemName: "trash.fill"),
//                    title: "Delete",
//                    backgroundColor: .systemRed,
//                    tint: .white) { print("deleted") },
//              .init(icon: UIImage(systemName: "archivebox.fill"),
//                    title: "Archive",
//                    backgroundColor: .systemGray,
//                    tint: .white) { print("archived") },
//          ])
//      view.addSubview(row)
//      NSLayoutConstraint.activate([
//          row.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//          row.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//          row.heightAnchor.constraint(equalToConstant: 64),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SwipeActionRow: UIView, UIGestureRecognizerDelegate {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Resting width of each revealed action button.
        var actionWidth: CGFloat = 76
        /// Whether dragging past `fullSwipeThreshold` triggers the first action.
        var fullSwipeEnabled: Bool = true
        /// Fraction of the row's width that arms the full-swipe trigger.
        var fullSwipeThreshold: CGFloat = 0.55
        /// Corner radius applied to the content + action area.
        var cornerRadius: CGFloat = 0
        /// Spring used for snap-open / snap-closed / full-swipe animations.
        var animation: Inlay.Spring = .snappy
        /// Vertical spacing between an action's icon and its title.
        var iconTitleSpacing: CGFloat = 4
        /// Font for action titles.
        var font: UIFont = .systemFont(ofSize: 13, weight: .semibold)
        /// Haptic feedback when an action arms (full-swipe) or fires.
        var hapticsEnabled: Bool = true
        /// Extra resistance applied when over-dragging past the resting open
        /// position, or when dragging a side that has no actions (rubber-band).
        var elasticOverscroll: CGFloat = 0.55

        static let `default` = Configuration()
    }

    // MARK: - Action

    /// A single revealed action. Provide an SF Symbol (or any image) and/or a
    /// title, the colors to paint it with, and a closure to run on tap.
    struct Action {
        let icon: UIImage?
        let title: String?
        let backgroundColor: UIColor
        let tint: UIColor
        let onTap: () -> Void

        init(
            icon: UIImage?,
            title: String? = nil,
            backgroundColor: UIColor,
            tint: UIColor,
            onTap: @escaping () -> Void
        ) {
            self.icon = icon
            self.title = title
            self.backgroundColor = backgroundColor
            self.tint = tint
            self.onTap = onTap
        }
    }

    // MARK: - Side

    private enum Side {
        case leading
        case trailing
    }

    // MARK: - Private state

    private let configuration: Configuration
    private let contentView: UIView
    private let leadingActions: [Action]
    private let trailingActions: [Action]

    private let clip = UIView()
    private let contentHost = UIView()
    private let leadingStack = UIStackView()
    private let trailingStack = UIStackView()

    private var leadingButtons: [UIButton] = []
    private var trailingButtons: [UIButton] = []

    /// Drives the content's horizontal offset. Positive → revealing leading
    /// actions; negative → revealing trailing actions.
    private var contentLeading: NSLayoutConstraint!
    private var offset: CGFloat = 0
    private var panStartOffset: CGFloat = 0
    private var armedSide: Side?

    private var leadingWidth: CGFloat { CGFloat(leadingActions.count) * configuration.actionWidth }
    private var trailingWidth: CGFloat { CGFloat(trailingActions.count) * configuration.actionWidth }

    // MARK: - Init

    init(
        contentView: UIView,
        leadingActions: [Action] = [],
        trailingActions: [Action] = [],
        configuration: Configuration = .default
    ) {
        self.contentView = contentView
        self.leadingActions = leadingActions
        self.trailingActions = trailingActions
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.contentView = UIView()
        self.leadingActions = []
        self.trailingActions = []
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.clipsToBounds = true
        clip.layer.cornerRadius = configuration.cornerRadius
        clip.layer.cornerCurve = .continuous
        addSubview(clip)
        NSLayoutConstraint.activate([
            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setUpActionStacks()
        setUpContent()
        setUpGestures()
    }

    private func setUpActionStacks() {
        // Leading stack is pinned to the leading edge, sitting behind content.
        configure(stack: leadingStack)
        clip.addSubview(leadingStack)
        NSLayoutConstraint.activate([
            leadingStack.topAnchor.constraint(equalTo: clip.topAnchor),
            leadingStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            leadingStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
        ])
        leadingButtons = leadingActions.enumerated().map { index, action in
            makeButton(for: action, side: .leading, index: index)
        }
        leadingButtons.forEach { leadingStack.addArrangedSubview($0) }

        // Trailing stack is pinned to the trailing edge, sitting behind content.
        configure(stack: trailingStack)
        clip.addSubview(trailingStack)
        NSLayoutConstraint.activate([
            trailingStack.topAnchor.constraint(equalTo: clip.topAnchor),
            trailingStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            trailingStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        ])
        trailingButtons = trailingActions.enumerated().map { index, action in
            makeButton(for: action, side: .trailing, index: index)
        }
        trailingButtons.forEach { trailingStack.addArrangedSubview($0) }
    }

    private func configure(stack: UIStackView) {
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setUpContent() {
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(contentHost)

        contentLeading = contentHost.leadingAnchor.constraint(equalTo: clip.leadingAnchor)
        NSLayoutConstraint.activate([
            contentLeading,
            contentHost.topAnchor.constraint(equalTo: clip.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            contentHost.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
        ])
    }

    private func makeButton(for action: Action, side: Side, index: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = action.icon
        config.title = action.title
        config.baseForegroundColor = action.tint
        config.imagePlacement = .top
        config.imagePadding = configuration.iconTitleSpacing
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { [font = configuration.font] incoming in
                var out = incoming
                out.font = font
                return out
            }

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = action.backgroundColor
        button.widthAnchor.constraint(equalToConstant: configuration.actionWidth).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.fire(action)
        }, for: .touchUpInside)
        return button
    }

    // MARK: - Gestures

    private func setUpGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        contentHost.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        contentHost.addGestureRecognizer(tap)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).x

        switch gesture.state {
        case .began:
            panStartOffset = offset

        case .changed:
            var proposed = panStartOffset + translation
            proposed = resist(proposed)
            apply(offset: proposed)
            updateArm()

        case .ended, .cancelled, .failed:
            finishPan(velocity: gesture.velocity(in: self).x)

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard offset != 0 else { return }
        close()
    }

    /// Applies rubber-band resistance once the drag goes past the resting open
    /// position, or for any drag toward a side that has no actions.
    private func resist(_ value: CGFloat) -> CGFloat {
        let elastic = configuration.elasticOverscroll

        if value > 0 {
            guard !leadingActions.isEmpty else { return value * elastic }
            let rest = leadingWidth
            return value <= rest ? value : rest + (value - rest) * elastic
        } else if value < 0 {
            guard !trailingActions.isEmpty else { return value * elastic }
            let rest = trailingWidth
            return value >= -rest ? value : -rest + (value + rest) * elastic
        }
        return value
    }

    private func apply(offset newOffset: CGFloat) {
        offset = newOffset
        contentLeading.constant = newOffset
    }

    // MARK: - Full-swipe arming

    /// Lights up the full-swipe state (and fires a haptic on the transition)
    /// whenever the active drag passes the threshold for a side with actions.
    private func updateArm() {
        guard configuration.fullSwipeEnabled, bounds.width > 0 else { return }
        let trigger = bounds.width * configuration.fullSwipeThreshold
        let newArm: Side?
        if offset > trigger, !leadingActions.isEmpty {
            newArm = .leading
        } else if offset < -trigger, !trailingActions.isEmpty {
            newArm = .trailing
        } else {
            newArm = nil
        }

        if newArm != armedSide {
            armedSide = newArm
            if newArm != nil, configuration.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func finishPan(velocity: CGFloat) {
        // Armed full-swipe: slide all the way across, fire, then close.
        if let armed = armedSide {
            triggerFullSwipe(armed)
            return
        }

        let projected = offset + velocity * 0.15

        if offset > 0, !leadingActions.isEmpty {
            settle(open: projected > leadingWidth / 2, side: .leading)
        } else if offset < 0, !trailingActions.isEmpty {
            settle(open: projected < -trailingWidth / 2, side: .trailing)
        } else {
            animate(to: 0)
        }
    }

    private func settle(open: Bool, side: Side) {
        guard open else { animate(to: 0); return }
        switch side {
        case .leading:  animate(to: leadingWidth)
        case .trailing: animate(to: -trailingWidth)
        }
    }

    private func triggerFullSwipe(_ side: Side) {
        armedSide = nil
        let action = (side == .leading) ? leadingActions.first : trailingActions.first
        let target: CGFloat = (side == .leading) ? bounds.width : -bounds.width

        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        Inlay.SpringAnimator.animate(configuration.animation, animations: {
            self.apply(offset: target)
            self.layoutIfNeeded()
        }, completion: { [weak self] in
            action?.onTap()
            self?.snapClosedSilently()
        })
    }

    // MARK: - Actions

    private func fire(_ action: Action) {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        action.onTap()
        close()
    }

    // MARK: - Animation helpers

    private func animate(to target: CGFloat) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.apply(offset: target)
            self.layoutIfNeeded()
        }
    }

    private func snapClosedSilently() {
        apply(offset: 0)
        setNeedsLayout()
    }

    // MARK: - Public API

    /// Returns the row to its resting (closed) position.
    func close(animated: Bool = true) {
        armedSide = nil
        if animated {
            animate(to: 0)
        } else {
            apply(offset: 0)
        }
    }

    /// Opens to reveal the leading actions (no-op if there are none).
    func openLeading() {
        guard !leadingActions.isEmpty else { return }
        animate(to: leadingWidth)
    }

    /// Opens to reveal the trailing actions (no-op if there are none).
    func openTrailing() {
        guard !trailingActions.isEmpty else { return }
        animate(to: -trailingWidth)
    }

    // MARK: - Gesture gating

    /// Only claim the pan for horizontal drags so vertical scrolling in an
    /// enclosing scroll view still works.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }
}
