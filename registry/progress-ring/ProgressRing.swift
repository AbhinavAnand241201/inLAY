//
//  ProgressRing.swift
//  Inlay — component
//
//  A circular, determinate progress indicator with a gradient stroke, a track
//  ring behind it, rounded line caps, a center percentage label that counts up
//  as the ring fills, an optional glow dot at the leading tip of the arc, and
//  an optional indeterminate (spinning arc) mode.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `ProgressRing.Configuration`.
//
//      var config = ProgressRing.Configuration.default
//      config.gradientStartColor = .systemTeal
//      config.gradientEndColor   = .systemIndigo
//      config.lineWidth          = 14
//      config.showsTipGlow       = true
//
//      let ring = ProgressRing(configuration: config)
//      view.addSubview(ring)
//      NSLayoutConstraint.activate([
//          ring.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          ring.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//          ring.widthAnchor.constraint(equalToConstant: 160),
//          ring.heightAnchor.constraint(equalToConstant: 160),
//      ])
//      ring.setProgress(0.72, animated: true)
//
//      // Indeterminate spinner:
//      //   ring.startIndeterminate()  …  ring.stopIndeterminate()
//
//  Dependency: none
//

import UIKit

final class ProgressRing: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Thickness of the track + progress strokes.
        var lineWidth: CGFloat = 12
        /// Colour of the unfilled track ring behind the progress.
        var trackColor: UIColor = .secondarySystemFill
        /// Solid progress colour. Used when a gradient is not fully specified.
        var progressColor: UIColor = .tintColor
        /// Optional gradient start colour. When both start + end are set the
        /// stroke draws as a gradient instead of `progressColor`.
        var gradientStartColor: UIColor?
        /// Optional gradient end colour.
        var gradientEndColor: UIColor?
        /// Rounded line caps on the progress (and indeterminate) stroke.
        var roundedCaps: Bool = true
        /// Angle at which the ring begins. Default is the top (-90°).
        var startAngle: CGFloat = -.pi / 2
        /// Direction the ring fills.
        var clockwise: Bool = true
        /// Whether to show the counting-up percentage label in the centre.
        var showsPercentLabel: Bool = true
        /// Font for the percentage label.
        var percentFont: UIFont = .systemFont(ofSize: 34, weight: .bold)
        /// Colour for the percentage label.
        var percentColor: UIColor = .label
        /// Duration of the fill / count-up animation for `setProgress(_:animated:)`.
        var animationDuration: TimeInterval = 0.8
        /// Whether a soft glow dot rides the leading tip of the progress arc.
        var showsTipGlow: Bool = true

        static let `default` = Configuration()
    }

    // MARK: - Public state

    /// Current progress, 0...1.
    private(set) var progress: CGFloat = 0

    // MARK: - Private state

    private let configuration: Configuration

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let tipGlowLayer = CALayer()

    private let percentLabel = UILabel()

    private var isIndeterminate = false
    private var labelLink: CADisplayLink?
    private var labelAnimationStart: CFTimeInterval = 0
    private var labelFromValue: CGFloat = 0
    private var labelToValue: CGFloat = 0
    private var labelDuration: TimeInterval = 0

    private static let spinKey = "inlay.progressRing.spin"
    private static let strokeKey = "inlay.progressRing.stroke"

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

    deinit {
        labelLink?.invalidate()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        // Track ring (background).
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = configuration.trackColor.cgColor
        trackLayer.lineWidth = configuration.lineWidth
        trackLayer.lineCap = configuration.roundedCaps ? .round : .butt
        layer.addSublayer(trackLayer)

        // Progress ring — used either as a solid stroke, or as the alpha mask
        // for the gradient layer.
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = configuration.progressColor.cgColor
        progressLayer.lineWidth = configuration.lineWidth
        progressLayer.lineCap = configuration.roundedCaps ? .round : .butt
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0

        if usesGradient {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            gradientLayer.colors = [
                (configuration.gradientStartColor ?? configuration.progressColor).cgColor,
                (configuration.gradientEndColor ?? configuration.progressColor).cgColor,
            ]
            gradientLayer.mask = progressLayer
            layer.addSublayer(gradientLayer)
        } else {
            layer.addSublayer(progressLayer)
        }

        // Tip glow dot.
        if configuration.showsTipGlow {
            let tip = tipColor
            tipGlowLayer.backgroundColor = tip.cgColor
            tipGlowLayer.shadowColor = tip.cgColor
            tipGlowLayer.shadowOpacity = 0.9
            tipGlowLayer.shadowRadius = 6
            tipGlowLayer.shadowOffset = .zero
            tipGlowLayer.opacity = 0
            layer.addSublayer(tipGlowLayer)
        }

        // Centre percentage label.
        if configuration.showsPercentLabel {
            percentLabel.translatesAutoresizingMaskIntoConstraints = false
            percentLabel.textAlignment = .center
            percentLabel.font = configuration.percentFont
            percentLabel.textColor = configuration.percentColor
            percentLabel.adjustsFontSizeToFitWidth = true
            percentLabel.minimumScaleFactor = 0.5
            percentLabel.text = "0%"
            addSubview(percentLabel)
            NSLayoutConstraint.activate([
                percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                percentLabel.leadingAnchor.constraint(
                    greaterThanOrEqualTo: leadingAnchor, constant: 8),
                percentLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor, constant: -8),
            ])
        }
    }

    private var usesGradient: Bool {
        configuration.gradientStartColor != nil && configuration.gradientEndColor != nil
    }

    private var tipColor: UIColor {
        configuration.gradientEndColor ?? configuration.progressColor
    }

    // MARK: - Public API

    /// Sets progress in 0...1 (clamped). When `animated`, the stroke fills and
    /// the centre label counts up over `configuration.animationDuration`.
    func setProgress(_ value: CGFloat, animated: Bool) {
        if isIndeterminate { stopIndeterminate() }

        let clamped = max(0, min(value, 1))
        let previous = progress
        progress = clamped

        progressLayer.removeAnimation(forKey: Self.strokeKey)

        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = previous
            animation.toValue = clamped
            animation.duration = configuration.animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressLayer.strokeEnd = clamped
            progressLayer.add(animation, forKey: Self.strokeKey)

            animateTipGlow(from: previous, to: clamped,
                           duration: configuration.animationDuration)
            startLabelCountUp(from: previous, to: clamped,
                              duration: configuration.animationDuration)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = clamped
            CATransaction.commit()
            updateTipGlowPosition(forFraction: clamped)
            tipGlowLayer.opacity = clamped > 0.001 ? 1 : 0
            setLabel(to: clamped)
        }
    }

    /// Starts a continuously rotating partial-arc spinner. The determinate
    /// progress value is preserved and restored by `stopIndeterminate()`.
    func startIndeterminate() {
        guard !isIndeterminate else { return }
        isIndeterminate = true

        labelLink?.invalidate()
        labelLink = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0.25
        tipGlowLayer.opacity = 0
        CATransaction.commit()

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * CGFloat.pi
        spin.duration = 1.0
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        let host: CALayer = usesGradient ? gradientLayer : progressLayer
        host.add(spin, forKey: Self.spinKey)
    }

    /// Stops the indeterminate spinner and restores the determinate progress.
    func stopIndeterminate() {
        guard isIndeterminate else { return }
        isIndeterminate = false

        let host: CALayer = usesGradient ? gradientLayer : progressLayer
        host.removeAnimation(forKey: Self.spinKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = progress
        CATransaction.commit()

        updateTipGlowPosition(forFraction: progress)
        tipGlowLayer.opacity = progress > 0.001 ? 1 : 0
        setLabel(to: progress)
    }

    // MARK: - Tip glow

    private func animateTipGlow(from: CGFloat, to: CGFloat, duration: TimeInterval) {
        guard configuration.showsTipGlow else { return }
        tipGlowLayer.opacity = to > 0.001 ? 1 : 0

        let fromPoint = pointOnRing(forFraction: from)
        let toPoint = pointOnRing(forFraction: to)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(cgPoint: fromPoint)
        move.toValue = NSValue(cgPoint: toPoint)
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tipGlowLayer.position = toPoint
        CATransaction.commit()
        tipGlowLayer.add(move, forKey: "inlay.tip.move")
    }

    private func updateTipGlowPosition(forFraction fraction: CGFloat) {
        guard configuration.showsTipGlow else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tipGlowLayer.position = pointOnRing(forFraction: fraction)
        CATransaction.commit()
    }

    private func pointOnRing(forFraction fraction: CGFloat) -> CGPoint {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = ringRadius
        let sweep = 2 * CGFloat.pi * fraction
        let angle = configuration.clockwise
            ? configuration.startAngle + sweep
            : configuration.startAngle - sweep
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    // MARK: - Label count-up

    private func startLabelCountUp(from: CGFloat, to: CGFloat, duration: TimeInterval) {
        guard configuration.showsPercentLabel else { return }
        labelLink?.invalidate()
        labelFromValue = from
        labelToValue = to
        labelDuration = duration
        labelAnimationStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepLabel))
        link.add(to: .main, forMode: .common)
        labelLink = link
    }

    @objc private func stepLabel() {
        let elapsed = CACurrentMediaTime() - labelAnimationStart
        let t = labelDuration > 0 ? min(elapsed / labelDuration, 1) : 1
        // Match the stroke's ease-in-ease-out feel.
        let eased = t * t * (3 - 2 * t)
        let value = labelFromValue + (labelToValue - labelFromValue) * CGFloat(eased)
        setLabel(to: value)
        if t >= 1 {
            labelLink?.invalidate()
            labelLink = nil
            setLabel(to: labelToValue)
        }
    }

    private func setLabel(to value: CGFloat) {
        guard configuration.showsPercentLabel else { return }
        percentLabel.text = "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Layout

    private var ringRadius: CGFloat {
        (min(bounds.width, bounds.height) - configuration.lineWidth) / 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = ringRadius
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: configuration.startAngle,
            endAngle: configuration.startAngle + (configuration.clockwise ? 1 : -1) * 2 * .pi,
            clockwise: configuration.clockwise
        ).cgPath

        trackLayer.frame = bounds
        trackLayer.path = path

        progressLayer.frame = bounds
        progressLayer.path = path

        if usesGradient {
            gradientLayer.frame = bounds
        }

        // Tip glow sizing tracks the line width.
        let dot = configuration.lineWidth
        tipGlowLayer.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
        tipGlowLayer.cornerRadius = dot / 2
        if !isIndeterminate {
            updateTipGlowPosition(forFraction: progress)
            tipGlowLayer.opacity = (configuration.showsTipGlow && progress > 0.001) ? 1 : 0
        }
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        else { return }

        // Resolve dynamic colours for the CALayers, which don't auto-update.
        trackLayer.strokeColor = configuration.trackColor.cgColor
        if !usesGradient {
            progressLayer.strokeColor = configuration.progressColor.cgColor
        } else {
            gradientLayer.colors = [
                (configuration.gradientStartColor ?? configuration.progressColor).cgColor,
                (configuration.gradientEndColor ?? configuration.progressColor).cgColor,
            ]
        }
        if configuration.showsTipGlow {
            tipGlowLayer.backgroundColor = tipColor.cgColor
            tipGlowLayer.shadowColor = tipColor.cgColor
        }
    }
}
