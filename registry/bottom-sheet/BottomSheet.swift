//
//  BottomSheet.swift
//  Inlay — component
//
//  A draggable, detent-snapping bottom sheet you present over any view —
//  no UIViewController transition, no presentation controller. It pastes
//  anywhere and behaves like the iOS system sheet: a dimmed backdrop, a
//  rounded container with a grabber pill, fluid drag with rubber-banding
//  past the top detent, snap-to-nearest on release, and swipe-down-to-dismiss.
//  Everything is tuned through `BottomSheet.Configuration`.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//
//      let content = UILabel()
//      content.text = "Hello from a sheet"
//      content.textAlignment = .center
//
//      var config = BottomSheet.Configuration.default
//      config.detents = [.medium, .large]
//      config.initialDetent = .medium
//
//      let sheet = BottomSheet(contentView: content, configuration: config)
//      sheet.onDetentChange = { print("now at \($0)") }
//      sheet.onDismiss = { print("dismissed") }
//      sheet.present(in: view)            // any UIView host
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class BottomSheet: UIView {

    // MARK: - Configuration

    /// Every visual + behavioural knob. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {

        /// Resting positions the sheet can snap to. Heights are resolved
        /// against the host view at present-time. Nested so the name is safe.
        enum Detent: Equatable {
            /// Roughly half the host height.
            case medium
            /// The full host height minus `topInsetForLarge` and the safe area.
            case large
            /// A custom fraction (0...1) of the host height.
            case fraction(CGFloat)
            /// An explicit point height.
            case height(CGFloat)
        }

        /// Detents the sheet may rest at. Resolved + sorted by height at present.
        var detents: [Detent] = [.medium, .large]
        /// Where the sheet opens. Falls back to the smallest detent if absent.
        var initialDetent: Detent = .medium
        /// Corner radius of the sheet's top corners.
        var cornerRadius: CGFloat = 24
        /// Whether the grabber pill is shown.
        var grabberVisible: Bool = true
        /// Grabber pill color.
        var grabberColor: UIColor = .systemFill
        /// Backdrop dim color (alpha is driven separately, see below).
        var backdropColor: UIColor = .black
        /// Backdrop alpha when the sheet sits at its largest detent.
        var backdropMaxAlpha: CGFloat = 0.45
        /// Tap the backdrop to dismiss.
        var dismissOnBackdropTap: Bool = true
        /// Drag below the smallest detent past the threshold to dismiss.
        var dismissOnSwipeDown: Bool = true
        /// Sheet container background. Dynamic color → free dark mode.
        var sheetBackgroundColor: UIColor = .secondarySystemBackground
        /// Spring used for snapping, presenting and dismissing. (Shared token.)
        var animation: Inlay.Spring = .snappy
        /// Gap left above the sheet at the `.large` detent (below the safe area).
        var topInsetForLarge: CGFloat = 10
        /// Haptic on detent snap.
        var hapticsEnabled: Bool = true
        /// Drag distance below the smallest detent that triggers dismissal.
        var dismissThreshold: CGFloat = 80
        /// How stiff the rubber-band feels past the largest detent (0...1).
        var rubberBandFactor: CGFloat = 0.55

        static let `default` = Configuration()
    }

    // MARK: - Callbacks

    /// Fires whenever the resting detent changes (after a snap settles).
    var onDetentChange: ((Configuration.Detent) -> Void)?
    /// Fires once after the sheet has fully dismissed and left the hierarchy.
    var onDismiss: (() -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private let contentView: UIView

    private let backdrop = UIView()
    private let sheetContainer = UIView()
    private let grabber = UIView()
    private let contentHost = UIView()

    /// Distance from the host top to the sheet's top edge. Lower = taller sheet.
    private var sheetTopConstraint: NSLayoutConstraint?
    /// Resolved detent offsets (sheet top from host top), sorted tallest→shortest
    /// is NOT how we store them; we keep them paired with their detent.
    private var resolvedDetents: [(detent: Configuration.Detent, top: CGFloat)] = []
    private var currentDetent: Configuration.Detent
    private var hostHeight: CGFloat = 0
    private var panStartTop: CGFloat = 0
    private var isPresented = false

    // MARK: - Init

    init(contentView: UIView, configuration: Configuration = .default) {
        self.contentView = contentView
        self.configuration = configuration
        self.currentDetent = configuration.initialDetent
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.contentView = UIView()
        self.configuration = .default
        self.currentDetent = Configuration.default.initialDetent
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true

        setUpBackdrop()
        setUpSheet()
        setUpShadow()
        setUpGrabber()
        setUpContent()
        setUpGestures()
    }

    private func setUpBackdrop() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.backgroundColor = configuration.backdropColor
        backdrop.alpha = 0
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func setUpSheet() {
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.backgroundColor = configuration.sheetBackgroundColor
        sheetContainer.layer.cornerRadius = configuration.cornerRadius
        sheetContainer.layer.cornerCurve = .continuous
        sheetContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainer.clipsToBounds = true
        addSubview(sheetContainer)

        // Pinned wide; height runs past the bottom so an over-pull never
        // exposes a gap below the sheet.
        let top = sheetContainer.topAnchor.constraint(equalTo: topAnchor)
        sheetTopConstraint = top
        NSLayoutConstraint.activate([
            top,
            sheetContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            sheetContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Extend below the host so the rounded sheet never reveals a seam.
            sheetContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 60),
        ])
    }

    private func setUpShadow() {
        // Shadow lives on the outer view (self); the container clips. Because
        // self is full-screen we can't shadow-path the whole view, so we host
        // the shadow on a dedicated layer-backed wrapper: use the container's
        // own superview layer. Simplest correct approach: shadow on self with a
        // path recomputed in layoutSubviews to trace the sheet's top edge.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: -6)
    }

    private func setUpGrabber() {
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = configuration.grabberColor
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous
        grabber.isHidden = !configuration.grabberVisible
        sheetContainer.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: sheetContainer.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: sheetContainer.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
        ])
    }

    private func setUpContent() {
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(contentHost)

        let grabberGap: CGFloat = configuration.grabberVisible ? 20 : 8
        NSLayoutConstraint.activate([
            contentHost.topAnchor.constraint(equalTo: sheetContainer.topAnchor, constant: grabberGap),
            contentHost.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }

    private func setUpGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        backdrop.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sheetContainer.addGestureRecognizer(pan)
    }

    // MARK: - Presentation

    /// Adds the sheet over `parent`, pinned to its bounds, and animates up to
    /// the initial detent.
    func present(in parent: UIView, animated: Bool = true) {
        guard superview == nil else { return }
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])

        // Resolve geometry now that we're in the hierarchy.
        layoutIfNeeded()
        resolveDetents()

        let targetTop = top(for: currentDetent)
        // Start fully off-screen below.
        sheetTopConstraint?.constant = hostHeight
        backdrop.alpha = 0
        layoutIfNeeded()

        isPresented = true
        let settle = { [weak self] in
            guard let self else { return }
            self.sheetTopConstraint?.constant = targetTop
            self.backdrop.alpha = self.backdropAlpha(forTop: targetTop)
            self.layoutIfNeeded()
        }

        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, animations: settle) { [weak self] in
                self?.onDetentChange?(self?.currentDetent ?? .medium)
            }
        } else {
            settle()
            onDetentChange?(currentDetent)
        }
    }

    /// Animates the sheet off-screen and removes it from the hierarchy.
    func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let finish = { [weak self] in
            guard let self else { return }
            self.removeFromSuperview()
            self.onDismiss?()
        }

        let slideDown = { [weak self] in
            guard let self else { return }
            self.sheetTopConstraint?.constant = self.hostHeight
            self.backdrop.alpha = 0
            self.layoutIfNeeded()
        }

        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, animations: slideDown, completion: finish)
        } else {
            slideDown()
            finish()
        }
    }

    /// Programmatically snap to a specific detent (must be one of the resolved
    /// detents, or the nearest is used).
    func move(to detent: Configuration.Detent, animated: Bool = true) {
        guard isPresented else { currentDetent = detent; return }
        let resolvedTop = top(for: detent)
        animateSheet(toTop: resolvedTop, settleDetent: detent, animated: animated)
    }

    // MARK: - Detent resolution

    private func resolveDetents() {
        hostHeight = bounds.height
        let safeTop = safeAreaInsets.top
        let detents = configuration.detents.isEmpty ? [Configuration.Detent.medium] : configuration.detents

        // Map each detent to a sheet height, then to a "top" offset from host top.
        var pairs: [(Configuration.Detent, CGFloat)] = detents.map { detent in
            let height = sheetHeight(for: detent, safeTop: safeTop)
            let top = max(0, hostHeight - height)
            return (detent, top)
        }
        // Sort by top ascending (tallest sheet first → smallest top value).
        pairs.sort { $0.1 < $1.1 }
        resolvedDetents = pairs.map { (detent: $0.0, top: $0.1) }
    }

    private func sheetHeight(for detent: Configuration.Detent, safeTop: CGFloat) -> CGFloat {
        switch detent {
        case .medium:
            return hostHeight * 0.5
        case .large:
            return hostHeight - safeTop - configuration.topInsetForLarge
        case .fraction(let f):
            return hostHeight * max(0, min(f, 1))
        case .height(let h):
            return min(max(0, h), hostHeight - safeTop - configuration.topInsetForLarge)
        }
    }

    /// The resolved top offset for a detent, falling back to the nearest known.
    private func top(for detent: Configuration.Detent) -> CGFloat {
        if let exact = resolvedDetents.first(where: { $0.detent == detent }) {
            return exact.top
        }
        // Not an installed detent → resolve its height ad hoc.
        let height = sheetHeight(for: detent, safeTop: safeAreaInsets.top)
        return max(0, hostHeight - height)
    }

    /// Smallest sheet (largest top value) — the dismissal boundary.
    private var minTop: CGFloat { resolvedDetents.map { $0.top }.max() ?? hostHeight * 0.5 }
    /// Largest sheet (smallest top value) — the rubber-band ceiling.
    private var maxTop: CGFloat { resolvedDetents.map { $0.top }.min() ?? 0 }

    // MARK: - Backdrop interpolation

    /// Backdrop alpha scales with how far open the sheet is: full at the
    /// largest detent, fading toward the smallest.
    private func backdropAlpha(forTop top: CGFloat) -> CGFloat {
        let openTop = maxTop          // tallest sheet
        let closedTop = hostHeight    // fully gone
        guard closedTop > openTop else { return configuration.backdropMaxAlpha }
        let progress = (closedTop - top) / (closedTop - openTop)
        return max(0, min(progress, 1)) * configuration.backdropMaxAlpha
    }

    // MARK: - Gestures

    @objc private func handleBackdropTap() {
        guard configuration.dismissOnBackdropTap else { return }
        dismiss(animated: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).y

        switch gesture.state {
        case .began:
            panStartTop = sheetTopConstraint?.constant ?? minTop

        case .changed:
            var newTop = panStartTop + translation
            // Rubber-band when dragging above the tallest detent.
            if newTop < maxTop {
                let overshoot = maxTop - newTop
                newTop = maxTop - overshoot * configuration.rubberBandFactor
            }
            sheetTopConstraint?.constant = newTop
            backdrop.alpha = backdropAlpha(forTop: max(newTop, maxTop))

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            let projectedTop = (sheetTopConstraint?.constant ?? minTop) + velocity * 0.12

            // Dismiss if flung/dragged below the smallest detent past threshold.
            if configuration.dismissOnSwipeDown,
               projectedTop > minTop + configuration.dismissThreshold {
                dismiss(animated: true)
                return
            }

            let target = nearestDetent(toTop: projectedTop)
            animateSheet(toTop: target.top, settleDetent: target.detent, animated: true)

        default:
            break
        }
    }

    private func nearestDetent(toTop top: CGFloat) -> (detent: Configuration.Detent, top: CGFloat) {
        guard !resolvedDetents.isEmpty else { return (currentDetent, minTop) }
        return resolvedDetents.min { lhs, rhs in
            abs(lhs.top - top) < abs(rhs.top - top)
        }!
    }

    private func animateSheet(
        toTop targetTop: CGFloat,
        settleDetent: Configuration.Detent,
        animated: Bool
    ) {
        let detentChanged = settleDetent != currentDetent
        currentDetent = settleDetent

        let apply = { [weak self] in
            guard let self else { return }
            self.sheetTopConstraint?.constant = targetTop
            self.backdrop.alpha = self.backdropAlpha(forTop: targetTop)
            self.layoutIfNeeded()
        }

        let settle = { [weak self] in
            guard let self else { return }
            if detentChanged, self.configuration.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            if detentChanged { self.onDetentChange?(settleDetent) }
        }

        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, animations: apply, completion: settle)
        } else {
            apply()
            settle()
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // Keep detent geometry correct across rotation / size changes.
        let previousHeight = hostHeight
        if bounds.height != previousHeight, isPresented {
            resolveDetents()
            if let pair = resolvedDetents.first(where: { $0.detent == currentDetent }) {
                sheetTopConstraint?.constant = pair.top
            }
        }

        // Shadow path traces the sheet's rounded top edge for a crisp,
        // performant shadow that follows the sheet as it slides.
        let top = sheetTopConstraint?.constant ?? 0
        let sheetRect = CGRect(
            x: 0,
            y: top,
            width: bounds.width,
            height: max(0, bounds.height - top) + 60
        )
        layer.shadowPath = UIBezierPath(
            roundedRect: sheetRect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(
                width: configuration.cornerRadius,
                height: configuration.cornerRadius
            )
        ).cgPath
    }
}
