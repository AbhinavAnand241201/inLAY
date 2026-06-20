//
//  StatusFeedbackView.swift
//  Inlay — component
//
//  An animated success / error badge: a ring strokes itself on, the symbol
//  (checkmark or cross) draws after it, and the whole badge springs in with a
//  matching success/error haptic. Great for confirmation overlays and toasts.
//
//  ── How to use ────────────────────────────────────────────────────────────
//      let done = StatusFeedbackView()                 // .success by default
//      view.addSubview(done)
//      done.translatesAutoresizingMaskIntoConstraints = false
//      NSLayoutConstraint.activate([
//          done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          done.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//      // It plays automatically on screen. To show an error instead:
//      var config = StatusFeedbackView.Configuration.default
//      config.status = .error
//      let failed = StatusFeedbackView(configuration: config)
//      // Replay any time:  failed.replay()
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class StatusFeedbackView: UIView {

    enum Status { case success, error }

    // MARK: - Configuration

    struct Configuration {
        var status: Status = .success
        var successColor: UIColor = .systemGreen
        var errorColor: UIColor = .systemRed
        var lineWidth: CGFloat = 5
        var size: CGFloat = 72
        /// Spring used for the entrance pop. (Shared design token.)
        var animation: Inlay.Spring = .playful
        /// Seconds for the ring to draw.
        var ringDuration: CFTimeInterval = 0.4
        /// Seconds for the symbol to draw, after the ring.
        var symbolDuration: CFTimeInterval = 0.25
        var hapticsEnabled: Bool = true

        static let `default` = Configuration()
    }

    // MARK: - State

    private let configuration: Configuration
    private let ringLayer = CAShapeLayer()
    private let symbolLayer = CAShapeLayer()
    private var hasPlayed = false

    private var tint: UIColor {
        configuration.status == .success ? configuration.successColor : configuration.errorColor
    }

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: configuration.size, height: configuration.size))
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: configuration.size, height: configuration.size)
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        for l in [ringLayer, symbolLayer] {
            l.fillColor = UIColor.clear.cgColor
            l.strokeColor = tint.cgColor
            l.lineWidth = configuration.lineWidth
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        ringLayer.frame = b
        symbolLayer.frame = b
        ringLayer.path = UIBezierPath(
            ovalIn: b.insetBy(dx: configuration.lineWidth, dy: configuration.lineWidth)).cgPath
        symbolLayer.path = symbolPath(in: b).cgPath
    }

    private func symbolPath(in b: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        let w = b.width, h = b.height
        switch configuration.status {
        case .success:
            p.move(to: CGPoint(x: w * 0.30, y: h * 0.52))
            p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.66))
            p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.36))
        case .error:
            p.move(to: CGPoint(x: w * 0.36, y: h * 0.36))
            p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.64))
            p.move(to: CGPoint(x: w * 0.64, y: h * 0.36))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.64))
        }
        return p
    }

    // MARK: - Animation

    /// Plays the draw-on animation once. Safe to call manually.
    func play() {
        guard !hasPlayed else { return }
        hasPlayed = true
        layoutIfNeeded()

        let ring = CABasicAnimation(keyPath: "strokeEnd")
        ring.fromValue = 0
        ring.toValue = 1
        ring.duration = configuration.ringDuration
        ring.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.fillMode = .backwards
        ringLayer.add(ring, forKey: "ring")

        // Symbol holds at strokeEnd 0 (fillMode .backwards + future beginTime),
        // then draws once the ring finishes.
        let sym = CABasicAnimation(keyPath: "strokeEnd")
        sym.fromValue = 0
        sym.toValue = 1
        sym.duration = configuration.symbolDuration
        sym.beginTime = CACurrentMediaTime() + configuration.ringDuration
        sym.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sym.fillMode = .backwards
        symbolLayer.strokeEnd = 1
        symbolLayer.add(sym, forKey: "sym")

        transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        Inlay.SpringAnimator.animate(configuration.animation) { self.transform = .identity }

        if configuration.hapticsEnabled {
            let type: UINotificationFeedbackGenerator.FeedbackType =
                configuration.status == .success ? .success : .error
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }
    }

    /// Resets and plays again.
    func replay() {
        ringLayer.removeAllAnimations()
        symbolLayer.removeAllAnimations()
        hasPlayed = false
        play()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.play() }
    }
}
