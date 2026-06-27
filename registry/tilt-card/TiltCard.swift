//
//  TiltCard.swift
//  Inlay — component
//
//  An interactive 3D parallax tilt card. Wrap any view and it tilts in 3D
//  toward the touch point (or the device's attitude in gyro mode), like a
//  holographic trading card. A specular "sheen" glare tracks the tilt and the
//  drop shadow shifts to sell the depth. On release it springs back to flat.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `TiltCard.Configuration`.
//
//      let poster = UIImageView(image: UIImage(named: "card-art"))
//      poster.contentMode = .scaleAspectFill
//
//      let card = TiltCard(contentView: poster)             // touch / drag mode
//      view.addSubview(card)
//      NSLayoutConstraint.activate([
//          card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//          card.widthAnchor.constraint(equalToConstant: 260),
//          card.heightAnchor.constraint(equalToConstant: 360),
//      ])
//
//      // Gyro variant — drive the tilt from device motion instead of touch:
//      var config = TiltCard.Configuration.default
//      config.useMotion = true
//      let motionCard = TiltCard(contentView: poster, configuration: config)
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit
import CoreMotion

final class TiltCard: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Maximum rotation, in degrees, at the card's edges.
        var maxTilt: CGFloat = 14
        /// Perspective distance (points). Smaller = more dramatic 3D.
        var perspective: CGFloat = 700
        /// Corner radius of the card. `cornerCurve` is always `.continuous`.
        var cornerRadius: CGFloat = 22
        /// Whether the specular sheen overlay is drawn.
        var glareEnabled: Bool = true
        /// Colour of the sheen highlight.
        var glareColor: UIColor = .white
        /// Peak opacity of the sheen (0...1).
        var glareIntensity: CGFloat = 0.35
        /// Whether the drop shadow shifts opposite the tilt for depth.
        var shadowFollowsTilt: Bool = true
        /// Drive tilt from device attitude (CoreMotion) instead of touch.
        /// Falls back gracefully when no motion hardware is available.
        var useMotion: Bool = false
        /// Spring back to flat when the touch ends.
        var springsBackOnRelease: Bool = true
        /// Slight lift (scale) while pressed.
        var scaleOnTouch: Bool = true
        /// Scale factor applied while pressed when `scaleOnTouch` is on.
        var touchScale: CGFloat = 1.03
        /// Spring used for spring-back and press feedback. (Shared token.)
        var animation: Inlay.Spring = .lively

        static let `default` = Configuration()
    }

    // MARK: - Public

    /// The view being tilted. Provided at init; pinned to the card's bounds.
    let contentView: UIView

    // MARK: - Private state

    private let configuration: Configuration
    private let container = UIView()
    private let glareLayer = CAGradientLayer()
    private let baseShadowOffset: CGSize
    private let baseShadowRadius: CGFloat
    private var motionManager: CMMotionManager?
    private var isTracking = false

    // MARK: - Init

    init(contentView: UIView, configuration: Configuration = .default) {
        self.contentView = contentView
        self.configuration = configuration
        self.baseShadowOffset = CGSize(width: 0, height: 12)
        self.baseShadowRadius = 24
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.contentView = UIView()
        self.configuration = .default
        self.baseShadowOffset = CGSize(width: 0, height: 12)
        self.baseShadowRadius = 24
        super.init(coder: coder)
        setUp()
    }

    deinit {
        motionManager?.stopDeviceMotionUpdates()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // Outer view carries the shadow and must NOT clip.
        setUpShadow()

        // Inner container clips the corner radius; it is the layer we tilt.
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

        // Content fills the container.
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        setUpGlare()

        if !configuration.useMotion {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            addGestureRecognizer(pan)
        }
    }

    private func setUpShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = baseShadowRadius
        layer.shadowOffset = baseShadowOffset
    }

    private func setUpGlare() {
        guard configuration.glareEnabled else { return }
        // A diagonal specular band. We move it opposite the tilt by adjusting
        // start/end points, and reveal it via opacity scaled by tilt magnitude.
        glareLayer.colors = [
            configuration.glareColor.withAlphaComponent(0).cgColor,
            configuration.glareColor.withAlphaComponent(configuration.glareIntensity).cgColor,
            configuration.glareColor.withAlphaComponent(0).cgColor,
        ]
        glareLayer.locations = [0.0, 0.5, 1.0]
        glareLayer.startPoint = CGPoint(x: 0, y: 0)
        glareLayer.endPoint = CGPoint(x: 1, y: 1)
        glareLayer.opacity = 0
        // Clip the glare to the card's rounded bounds.
        glareLayer.cornerRadius = configuration.cornerRadius
        glareLayer.masksToBounds = true
        container.layer.addSublayer(glareLayer)
    }

    // MARK: - Touch tracking

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isTracking = true
            if configuration.scaleOnTouch { applyTouchScale(true) }
            apply(point: gesture.location(in: self))
        case .changed:
            apply(point: gesture.location(in: self))
        case .ended, .cancelled, .failed:
            isTracking = false
            if configuration.scaleOnTouch { applyTouchScale(false) }
            if configuration.springsBackOnRelease { springBackToFlat() }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard !configuration.useMotion, let touch = touches.first else { return }
        isTracking = true
        if configuration.scaleOnTouch { applyTouchScale(true) }
        apply(point: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard !configuration.useMotion, isTracking, let touch = touches.first else { return }
        apply(point: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endTouchTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endTouchTracking()
    }

    private func endTouchTracking() {
        guard !configuration.useMotion, isTracking else { return }
        isTracking = false
        if configuration.scaleOnTouch { applyTouchScale(false) }
        if configuration.springsBackOnRelease { springBackToFlat() }
    }

    /// Maps a point in the card's coordinate space to a normalized tilt and
    /// applies it.
    private func apply(point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Normalize to -1...1 around the centre.
        let nx = (point.x / bounds.width) * 2 - 1
        let ny = (point.y / bounds.height) * 2 - 1
        applyTilt(normalizedX: clamp(nx), normalizedY: clamp(ny), animated: false)
    }

    // MARK: - Tilt math

    /// Applies a tilt for a normalized input where `x`/`y` are in -1...1.
    /// Touching the right edge (x = +1) rotates the card so its right side
    /// recedes; touching the bottom (y = +1) tips the bottom back.
    private func applyTilt(normalizedX nx: CGFloat, normalizedY ny: CGFloat, animated: Bool) {
        let maxRadians = configuration.maxTilt * .pi / 180
        // Pointer to the right → rotate about Y so the right edge goes back.
        let rotateY = nx * maxRadians
        // Pointer down → rotate about X so the bottom edge goes back.
        let rotateX = -ny * maxRadians

        var transform = CATransform3DIdentity
        transform.m34 = -1 / configuration.perspective
        transform = CATransform3DRotate(transform, rotateX, 1, 0, 0)
        transform = CATransform3DRotate(transform, rotateY, 0, 1, 0)

        let updates = {
            self.container.layer.transform = transform
            self.updateGlare(normalizedX: nx, normalizedY: ny)
            self.updateShadow(normalizedX: nx, normalizedY: ny)
        }

        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, updates)
        } else {
            // Disable implicit CA animation for snappy 1:1 tracking.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updates()
            CATransaction.commit()
        }
    }

    /// Move the sheen opposite the tilt and scale its strength by how far the
    /// card is tipped.
    private func updateGlare(normalizedX nx: CGFloat, normalizedY ny: CGFloat) {
        guard configuration.glareEnabled else { return }
        let magnitude = min(1, hypot(nx, ny))
        glareLayer.opacity = Float(magnitude)
        // Slide the band toward the high (lit) corner — opposite the push.
        let dx = -nx * 0.5
        let dy = -ny * 0.5
        glareLayer.startPoint = CGPoint(x: 0.5 + dx - 0.5, y: 0.5 + dy - 0.5)
        glareLayer.endPoint = CGPoint(x: 0.5 + dx + 0.5, y: 0.5 + dy + 0.5)
    }

    /// Shift the drop shadow opposite the tilt so the card appears lifted.
    private func updateShadow(normalizedX nx: CGFloat, normalizedY ny: CGFloat) {
        guard configuration.shadowFollowsTilt else { return }
        let shift: CGFloat = 16
        layer.shadowOffset = CGSize(
            width: baseShadowOffset.width - nx * shift,
            height: baseShadowOffset.height - ny * shift
        )
    }

    private func springBackToFlat() {
        applyTilt(normalizedX: 0, normalizedY: 0, animated: true)
    }

    private func applyTouchScale(_ pressed: Bool) {
        guard configuration.scaleOnTouch else { return }
        let scale = pressed ? configuration.touchScale : 1
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        max(-1, min(1, value))
    }

    // MARK: - Motion (gyro mode)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard configuration.useMotion else { return }
        if window != nil {
            startMotion()
        } else {
            stopMotion()
        }
    }

    private func startMotion() {
        let manager = motionManager ?? CMMotionManager()
        motionManager = manager
        guard manager.isDeviceMotionAvailable else { return }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Map attitude roll/pitch (radians) to normalized -1...1, clamped
            // so resting at ~30° already hits the max tilt.
            let span: CGFloat = .pi / 6
            let nx = self.clamp(CGFloat(motion.attitude.roll) / span)
            let ny = self.clamp(CGFloat(motion.attitude.pitch) / span)
            self.applyTilt(normalizedX: nx, normalizedY: ny, animated: false)
        }
    }

    private func stopMotion() {
        motionManager?.stopDeviceMotionUpdates()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Anchor the 3D rotation about the card's centre.
        container.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glareLayer.frame = container.bounds
        glareLayer.cornerRadius = configuration.cornerRadius
        // Shadow path tracks the card shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }
}
