//
//  ExpandableCard.swift
//  Inlay — component
//
//  A card that shows a compact summary and, on tap, springs open to reveal
//  more detail. The height animates with a spring while the collapsed content
//  crossfades out and the expanded content fades + slides in. An optional
//  chevron rotates, and an optional scrim can dim the surroundings.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `ExpandableCard.Configuration`.
//
//      let summary = UILabel()
//      summary.text = "Today's summary"
//
//      let detail = UILabel()
//      detail.numberOfLines = 0
//      detail.text = "Lots more detail that only shows once expanded…"
//
//      let card = ExpandableCard(collapsedContent: summary, expandedContent: detail)
//      card.onToggle = { isExpanded in print("expanded:", isExpanded) }
//      stackView.addArrangedSubview(card)
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class ExpandableCard: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Corner radius of the card. Applied to the clipping inner container.
        var cornerRadius: CGFloat = 20
        /// Fill color of the card.
        var cardBackgroundColor: UIColor = .secondarySystemGroupedBackground
        /// Whether the outer view casts a soft shadow.
        var shadowEnabled: Bool = true
        /// Opacity of that shadow (ignored when `shadowEnabled == false`).
        var shadowOpacity: Float = 0.16
        /// Spring used for the expand/collapse + chevron animation.
        var animation: Inlay.Spring = .lively
        /// Whether the trailing chevron is shown (rotates when expanded).
        var showsChevron: Bool = true
        /// Tint of the chevron glyph.
        var chevronColor: UIColor = .tertiaryLabel
        /// Padding around the collapsed (summary) content.
        var collapsedInsets: UIEdgeInsets = .init(top: 16, left: 16, bottom: 16, right: 16)
        /// Padding around the expanded (detail) content.
        var expandedInsets: UIEdgeInsets = .init(top: 0, left: 16, bottom: 16, right: 16)
        /// Light haptic when the card toggles.
        var hapticsEnabled: Bool = true
        /// When true, a scrim fades in behind the card while it is expanded.
        var dimsSurroundings: Bool = false

        static let `default` = Configuration()
    }

    // MARK: - Public API

    /// Toggles the card open/closed, animating by default.
    var isExpanded: Bool {
        get { _isExpanded }
        set { setExpanded(newValue, animated: true) }
    }

    /// Called whenever the expanded state changes (taps and programmatic sets).
    var onToggle: ((Bool) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private let collapsedContent: UIView
    private let expandedContent: UIView

    private let container = UIView()
    private let collapsedHost = UIView()
    private let expandedHost = UIView()
    private let chevron = UIImageView()
    private var scrim: UIView?

    private var collapsedHeightConstraint: NSLayoutConstraint!
    private var expandedHeightConstraint: NSLayoutConstraint!

    private var _isExpanded = false

    // MARK: - Init

    init(
        collapsedContent: UIView,
        expandedContent: UIView,
        configuration: Configuration = .default
    ) {
        self.configuration = configuration
        self.collapsedContent = collapsedContent
        self.expandedContent = expandedContent
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.collapsedContent = UIView()
        self.expandedContent = UIView()
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
        container.backgroundColor = configuration.cardBackgroundColor
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

        setUpHosts()
        setUpChevron()
        setUpTap()
        applyState(expanded: _isExpanded)
    }

    private func setUpShadow() {
        guard configuration.shadowEnabled else { return }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = configuration.shadowOpacity
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    private func setUpHosts() {
        // Collapsed (summary) content — pinned to the top of the container.
        collapsedHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(collapsedHost)

        collapsedContent.translatesAutoresizingMaskIntoConstraints = false
        collapsedHost.addSubview(collapsedContent)

        let ci = configuration.collapsedInsets
        // Trailing inset leaves room for the chevron when shown.
        let collapsedTrailing = configuration.showsChevron ? ci.right + 28 : ci.right
        NSLayoutConstraint.activate([
            collapsedHost.topAnchor.constraint(equalTo: container.topAnchor),
            collapsedHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            collapsedHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            collapsedContent.topAnchor.constraint(equalTo: collapsedHost.topAnchor, constant: ci.top),
            collapsedContent.bottomAnchor.constraint(equalTo: collapsedHost.bottomAnchor, constant: -ci.bottom),
            collapsedContent.leadingAnchor.constraint(equalTo: collapsedHost.leadingAnchor, constant: ci.left),
            collapsedContent.trailingAnchor.constraint(equalTo: collapsedHost.trailingAnchor, constant: -collapsedTrailing),
        ])

        // Expanded (detail) content — sits below the summary.
        expandedHost.translatesAutoresizingMaskIntoConstraints = false
        expandedHost.clipsToBounds = true
        container.addSubview(expandedHost)

        expandedContent.translatesAutoresizingMaskIntoConstraints = false
        expandedHost.addSubview(expandedContent)

        let ei = configuration.expandedInsets
        NSLayoutConstraint.activate([
            expandedHost.topAnchor.constraint(equalTo: collapsedHost.bottomAnchor),
            expandedHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            expandedHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            expandedHost.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            expandedContent.topAnchor.constraint(equalTo: expandedHost.topAnchor, constant: ei.top),
            expandedContent.bottomAnchor.constraint(equalTo: expandedHost.bottomAnchor, constant: -ei.bottom),
            expandedContent.leadingAnchor.constraint(equalTo: expandedHost.leadingAnchor, constant: ei.left),
            expandedContent.trailingAnchor.constraint(equalTo: expandedHost.trailingAnchor, constant: -ei.right),
        ])

        // The card's height is driven by toggling these two constraints.
        // Collapsed: pin the container bottom to the summary, hiding the detail.
        collapsedHeightConstraint = container.bottomAnchor.constraint(equalTo: collapsedHost.bottomAnchor)
        // Expanded: the detail host (and its content) defines the bottom.
        expandedHeightConstraint = container.bottomAnchor.constraint(equalTo: expandedHost.bottomAnchor)
    }

    private func setUpChevron() {
        guard configuration.showsChevron else { return }
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.down")
        chevron.tintColor = configuration.chevronColor
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 14, weight: .semibold
        )
        container.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.centerYAnchor.constraint(equalTo: collapsedHost.centerYAnchor),
            chevron.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -configuration.collapsedInsets.right
            ),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func setUpTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    // MARK: - State

    private func applyState(expanded: Bool) {
        collapsedHeightConstraint.isActive = !expanded
        expandedHeightConstraint.isActive = expanded

        expandedHost.alpha = expanded ? 1 : 0
        expandedContent.alpha = expanded ? 1 : 0
        expandedContent.transform = expanded ? .identity : CGAffineTransform(translationX: 0, y: -8)
        collapsedContent.alpha = expanded ? 0.35 : 1
        chevron.transform = expanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        scrim?.alpha = expanded ? 1 : 0
    }

    @objc private func handleTap() {
        setExpanded(!_isExpanded, animated: true)
    }

    /// Expand or collapse the card. Animated by default.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != _isExpanded else { return }
        _isExpanded = expanded

        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        if configuration.dimsSurroundings {
            ensureScrim(for: expanded)
        }

        // Toggle constraints up front so layout has the new target.
        collapsedHeightConstraint.isActive = !expanded
        expandedHeightConstraint.isActive = expanded

        guard animated, window != nil else {
            applyState(expanded: expanded)
            superview?.layoutIfNeeded()
            onToggle?(expanded)
            return
        }

        Inlay.SpringAnimator.animate(
            configuration.animation,
            animations: {
                self.applyState(expanded: expanded)
                // Drive the height change up the chain so we resize in a stack.
                self.superview?.layoutIfNeeded()
            },
            completion: { [weak self] in
                self?.onToggle?(expanded)
            }
        )
    }

    // MARK: - Scrim

    private func ensureScrim(for expanding: Bool) {
        guard scrim == nil, expanding, let host = scrimHost() else { return }
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.alpha = 0
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped))
        view.addGestureRecognizer(tap)
        host.insertSubview(view, belowSubview: self)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        scrim = view
    }

    /// The nearest ancestor we can host a full-bleed scrim in. Walks up to a
    /// scroll view's enclosing view or the window's root view when possible.
    private func scrimHost() -> UIView? {
        var candidate: UIView? = superview
        while let current = candidate {
            if !(current is UIScrollView) { return current }
            candidate = current.superview
        }
        return superview
    }

    @objc private func scrimTapped() {
        setExpanded(false, animated: true)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard configuration.shadowEnabled else { return }
        // Shadow path tracks the card shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }
}
