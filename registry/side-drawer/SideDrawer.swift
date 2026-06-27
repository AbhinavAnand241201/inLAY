//
//  SideDrawer.swift
//  Inlay — component
//
//  A slide-in side drawer (hamburger menu). A content panel springs in from the
//  leading or trailing edge while a tappable dim backdrop fades in behind it.
//  Supports an optional parallax effect (the backdrop shifts/scales as the panel
//  opens) and an interactive edge-pan gesture that drags the drawer open/closed
//  and snaps on release. Light haptic on open and close.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SideDrawer.Configuration`.
//
//      let menu = UIView()                    // your menu content
//      menu.backgroundColor = .secondarySystemBackground
//
//      let drawer = SideDrawer(contentView: menu)
//      drawer.onOpen  = { print("opened")  }
//      drawer.onClose = { print("closed") }
//      drawer.present(in: view)               // installs + enables edge-pan
//
//      // later, e.g. from a bar-button:
//      drawer.toggle()
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SideDrawer: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Which screen edge the panel slides in from.
        var edge: Edge = .leading
        /// How the panel's width is derived.
        var width: Width = .fraction(0.8)
        /// Color of the dim backdrop behind the panel.
        var backdropColor: UIColor = .black
        /// Maximum opacity the backdrop reaches when fully open.
        var backdropMaxAlpha: CGFloat = 0.45
        /// Rounded corner on the panel's inner (screen-facing) edge only.
        var cornerRadius: CGFloat = 24
        /// Fill color of the panel itself.
        var panelBackgroundColor: UIColor = .systemBackground
        /// How far (in points) the backdrop/content shifts for parallax.
        /// `0` disables parallax.
        var parallaxAmount: CGFloat = 28
        /// Tapping the backdrop dismisses the drawer.
        var dismissOnBackdropTap: Bool = true
        /// A screen-edge pan can drag the drawer open.
        var enableEdgePanToOpen: Bool = true
        /// Spring used for open/close/snap animations. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Light haptic on open and close.
        var hapticsEnabled: Bool = true

        /// The edge the drawer attaches to.
        enum Edge {
            case leading
            case trailing
        }

        /// How the panel width is computed.
        enum Width {
            /// Fraction of the host view's width (e.g. `0.8`).
            case fraction(CGFloat)
            /// A fixed point width.
            case fixed(CGFloat)
        }

        static let `default` = Configuration()
    }

    // MARK: - Public API

    /// Fires after the open animation begins.
    var onOpen: (() -> Void)?
    /// Fires after the close animation begins.
    var onClose: (() -> Void)?

    /// `true` while the drawer is open (or animating toward open).
    private(set) var isOpen: Bool = false

    // MARK: - Private state

    private let configuration: Configuration
    private let contentView: UIView

    private let backdrop = UIView()
    private let panel = UIView()           // outer: carries the shadow, no clip
    private let panelClip = UIView()       // inner: clips corner radius + fill

    /// Leading-or-trailing constraint constant we animate to drive the panel.
    private var driveConstraint: NSLayoutConstraint?
    private var panelWidth: CGFloat = 0

    private weak var host: UIView?
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var panelPan: UIPanGestureRecognizer?

    // MARK: - Init

    init(contentView: UIView, configuration: Configuration = .default) {
        self.contentView = contentView
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.contentView = UIView()
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true

        setUpBackdrop()
        setUpPanel()
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

        if configuration.dismissOnBackdropTap {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
            backdrop.addGestureRecognizer(tap)
        }
    }

    private func setUpPanel() {
        // Outer panel carries the shadow and must NOT clip.
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.25
        panel.layer.shadowRadius = 24
        panel.layer.shadowOffset = shadowOffset(for: configuration.edge)
        addSubview(panel)

        // Inner clip view rounds the screen-facing corner and fills the panel.
        panelClip.translatesAutoresizingMaskIntoConstraints = false
        panelClip.backgroundColor = configuration.panelBackgroundColor
        panelClip.layer.cornerRadius = configuration.cornerRadius
        panelClip.layer.cornerCurve = .continuous
        panelClip.layer.maskedCorners = maskedCorners(for: configuration.edge)
        panelClip.clipsToBounds = true
        panel.addSubview(panelClip)
        NSLayoutConstraint.activate([
            panelClip.topAnchor.constraint(equalTo: panel.topAnchor),
            panelClip.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panelClip.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            panelClip.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        panelClip.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: panelClip.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: panelClip.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: panelClip.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: panelClip.trailingAnchor),
        ])

        // Panel is pinned top/bottom; its width is fixed, and a leading or
        // trailing constraint constant drives it on/off screen.
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // A pan on the panel can drag it closed (and back open while dragging).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanelPan(_:)))
        panel.addGestureRecognizer(pan)
        panelPan = pan
    }

    // MARK: - Presentation

    /// Installs the drawer (closed) into `parent`, pinned to its bounds, and
    /// wires up the edge-pan-to-open gesture if enabled.
    func present(in parent: UIView, animated: Bool = true) {
        guard host == nil else { return }
        host = parent

        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])

        installPanelWidthConstraint(in: parent)

        if configuration.enableEdgePanToOpen {
            let edge = UIScreenEdgePanGestureRecognizer(
                target: self, action: #selector(handleEdgePan(_:))
            )
            edge.edges = configuration.edge == .leading ? .left : .right
            parent.addGestureRecognizer(edge)
            edgePan = edge
        }

        // Start fully closed and let the host pass touches through until opened.
        isUserInteractionEnabled = false
        layoutIfNeeded()
        setDrivePosition(progress: 0)
    }

    private func installPanelWidthConstraint(in parent: UIView) {
        switch configuration.width {
        case .fraction(let f):
            let w = panel.widthAnchor.constraint(
                equalTo: widthAnchor, multiplier: max(0.1, min(f, 1.0))
            )
            w.isActive = true
        case .fixed(let points):
            panel.widthAnchor.constraint(equalToConstant: points).isActive = true
        }

        // The drive constraint pins the panel's outer edge; its constant moves
        // the panel between fully off-screen (closed) and flush (open).
        let drive: NSLayoutConstraint
        switch configuration.edge {
        case .leading:
            drive = panel.leadingAnchor.constraint(equalTo: leadingAnchor)
        case .trailing:
            drive = panel.trailingAnchor.constraint(equalTo: trailingAnchor)
        }
        drive.isActive = true
        driveConstraint = drive

        parent.layoutIfNeeded()
        panelWidth = panel.bounds.width
    }

    // MARK: - Open / Close

    func toggle() {
        isOpen ? dismiss() : open()
    }

    /// Opens the drawer.
    func open(animated: Bool = true) {
        guard host != nil, !isOpen else { return }
        ensureWidthResolved()
        isOpen = true
        isUserInteractionEnabled = true
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onOpen?()
        animateTo(progress: 1, animated: animated, completion: nil)
    }

    func dismiss(animated: Bool = true) {
        guard host != nil, isOpen else { return }
        isOpen = false
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onClose?()
        animateTo(progress: 0, animated: animated) { [weak self] in
            // Once closed, stop intercepting touches so the host stays usable.
            if self?.isOpen == false { self?.isUserInteractionEnabled = false }
        }
    }

    private func animateTo(progress: CGFloat, animated: Bool, completion: (() -> Void)?) {
        layoutIfNeeded()
        let work = { self.setDrivePosition(progress: progress); self.layoutIfNeeded() }
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, animations: work, completion: completion)
        } else {
            work()
            completion?()
        }
    }

    /// Maps `progress` (0 closed … 1 open) onto the drive constant, backdrop
    /// alpha, and parallax transform.
    private func setDrivePosition(progress: CGFloat) {
        let p = max(0, min(progress, 1))
        let hidden = -panelWidth      // panel pushed fully off its edge

        switch configuration.edge {
        case .leading:
            driveConstraint?.constant = hidden + panelWidth * p
        case .trailing:
            driveConstraint?.constant = -hidden - panelWidth * p
        }

        backdrop.alpha = configuration.backdropMaxAlpha * p
        applyParallax(progress: p)
    }

    private func applyParallax(progress: CGFloat) {
        guard configuration.parallaxAmount > 0 else {
            backdrop.transform = .identity
            return
        }
        let shift = configuration.parallaxAmount * progress
        let dir: CGFloat = configuration.edge == .leading ? 1 : -1
        let scale = 1 - 0.02 * progress
        backdrop.transform = CGAffineTransform(translationX: shift * dir, y: 0)
            .scaledBy(x: scale, y: scale)
    }

    // MARK: - Gestures

    @objc private func handleBackdropTap() {
        dismiss()
    }

    @objc private func handleEdgePan(_ gr: UIScreenEdgePanGestureRecognizer) {
        guard let host else { return }
        ensureWidthResolved()
        let translation = gr.translation(in: host).x
        let dir: CGFloat = configuration.edge == .leading ? 1 : -1
        let progress = max(0, min((translation * dir) / max(panelWidth, 1), 1))

        switch gr.state {
        case .began:
            isUserInteractionEnabled = true
        case .changed:
            setDrivePosition(progress: progress)
        case .ended, .cancelled, .failed:
            let velocity = gr.velocity(in: host).x * dir
            finishInteractive(progress: progress, velocity: velocity)
        default:
            break
        }
    }

    @objc private func handlePanelPan(_ gr: UIPanGestureRecognizer) {
        guard let host, isOpen || gr.state == .changed else { return }
        let translation = gr.translation(in: host).x
        let dir: CGFloat = configuration.edge == .leading ? 1 : -1
        // Dragging toward the edge (negative along open direction) closes it.
        let delta = (translation * dir) / max(panelWidth, 1)
        let progress = max(0, min(1 + delta, 1))

        switch gr.state {
        case .changed:
            setDrivePosition(progress: progress)
        case .ended, .cancelled, .failed:
            let velocity = gr.velocity(in: host).x * dir
            finishInteractive(progress: progress, velocity: velocity)
        default:
            break
        }
    }

    /// Snaps to open or closed based on how far the drag traveled and its
    /// release velocity.
    private func finishInteractive(progress: CGFloat, velocity: CGFloat) {
        let shouldOpen: Bool
        if abs(velocity) > 600 {
            shouldOpen = velocity > 0
        } else {
            shouldOpen = progress > 0.5
        }

        if shouldOpen {
            let wasOpen = isOpen
            isOpen = true
            isUserInteractionEnabled = true
            if !wasOpen {
                if configuration.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                onOpen?()
            }
            animateTo(progress: 1, animated: true, completion: nil)
        } else {
            let wasOpen = isOpen
            isOpen = false
            if wasOpen {
                if configuration.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                onClose?()
            }
            animateTo(progress: 0, animated: true) { [weak self] in
                if self?.isOpen == false { self?.isUserInteractionEnabled = false }
            }
        }
    }

    // MARK: - Helpers

    /// Width is read from the laid-out panel; re-resolve lazily in case the host
    /// laid out after `present`.
    private func ensureWidthResolved() {
        if panelWidth <= 0 {
            host?.layoutIfNeeded()
            layoutIfNeeded()
            panelWidth = panel.bounds.width
            if !isOpen { setDrivePosition(progress: 0) }
        }
    }

    private func shadowOffset(for edge: Configuration.Edge) -> CGSize {
        switch edge {
        case .leading:  return CGSize(width: 6, height: 0)
        case .trailing: return CGSize(width: -6, height: 0)
        }
    }

    private func maskedCorners(for edge: Configuration.Edge) -> CACornerMask {
        switch edge {
        case .leading:
            return [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]  // round trailing edge
        case .trailing:
            return [.layerMinXMinYCorner, .layerMinXMaxYCorner]  // round leading edge
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the panel for crisp, performant shadows.
        panel.layer.shadowPath = UIBezierPath(
            roundedRect: panel.bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }
}
