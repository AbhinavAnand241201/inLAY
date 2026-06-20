//
//  LoadingIndicator.swift
//  Inlay — component
//
//  A looping loading indicator with three styles: a rotating arc, three pulsing
//  dots, and equalizer bars. Pure CALayer animation, auto-starts on screen,
//  auto-stops when removed. No dependencies.
//
//  ── How to use ────────────────────────────────────────────────────────────
//      let loader = LoadingIndicator()             // .arc, .label color, 40pt
//      view.addSubview(loader)
//      loader.translatesAutoresizingMaskIntoConstraints = false
//      NSLayoutConstraint.activate([
//          loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          loader.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//      var config = LoadingIndicator.Configuration.default
//      config.style = .dots
//      let dots = LoadingIndicator(configuration: config)
//
//  Dependency: none
//

import UIKit

final class LoadingIndicator: UIView {

    // MARK: - Configuration

    struct Configuration {
        /// Visual style of the loop.
        var style: Style = .arc
        /// Stroke / fill color. Defaults to a dynamic color for dark mode.
        var color: UIColor = .label
        /// Stroke width for the `.arc` style.
        var lineWidth: CGFloat = 3
        /// Intrinsic side length of the indicator.
        var size: CGFloat = 40
        /// One full loop, in seconds.
        var period: CFTimeInterval = 1.0

        static let `default` = Configuration()

        enum Style { case arc, dots, bars }
    }

    // MARK: - State

    private let configuration: Configuration
    private var shapeLayers: [CAShapeLayer] = []
    private var isAnimating = false

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
        switch configuration.style {
        case .arc:  buildArc()
        case .dots: shapeLayers = buildFills(count: 3)
        case .bars: shapeLayers = buildFills(count: 4)
        }
    }

    private func buildArc() {
        let arc = CAShapeLayer()
        arc.fillColor = UIColor.clear.cgColor
        arc.strokeColor = configuration.color.cgColor
        arc.lineWidth = configuration.lineWidth
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.25
        layer.addSublayer(arc)
        shapeLayers = [arc]
    }

    private func buildFills(count: Int) -> [CAShapeLayer] {
        (0..<count).map { _ in
            let l = CAShapeLayer()
            l.fillColor = configuration.color.cgColor
            layer.addSublayer(l)
            return l
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        switch configuration.style {
        case .arc:
            let inset = configuration.lineWidth / 2
            shapeLayers.first?.frame = b
            shapeLayers.first?.path = UIBezierPath(ovalIn: b.insetBy(dx: inset, dy: inset)).cgPath
        case .dots:
            let d = b.height * 0.30
            let gap = (b.width - d * 3) / 2
            for (i, dot) in shapeLayers.enumerated() {
                dot.frame = CGRect(x: CGFloat(i) * (d + gap), y: (b.height - d) / 2,
                                   width: d, height: d)
                dot.path = UIBezierPath(ovalIn: dot.bounds).cgPath
            }
        case .bars:
            let n = CGFloat(shapeLayers.count)
            let w = b.width / (n * 2 - 1)
            for (i, bar) in shapeLayers.enumerated() {
                bar.frame = CGRect(x: CGFloat(i) * w * 2, y: 0, width: w, height: b.height)
                bar.path = UIBezierPath(roundedRect: bar.bounds, cornerRadius: w / 2).cgPath
            }
        }
    }

    // MARK: - Animation

    /// Starts the loop. Called automatically when the view enters a window.
    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        setNeedsLayout()
        layoutIfNeeded()
        applyAnimations()
    }

    /// Stops the loop and clears running animations.
    func stopAnimating() {
        isAnimating = false
        shapeLayers.forEach { $0.removeAllAnimations() }
    }

    private func applyAnimations() {
        switch configuration.style {
        case .arc:
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = configuration.period
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            shapeLayers.first?.add(spin, forKey: "spin")
        case .dots:
            stagger(keyPath: "transform.scale", values: [0.4, 1.0, 0.4], spread: 6)
        case .bars:
            stagger(keyPath: "transform.scale.y", values: [0.3, 1.0, 0.3], spread: 8)
        }
    }

    private func stagger(keyPath: String, values: [CGFloat], spread: Double) {
        for (i, l) in shapeLayers.enumerated() {
            let anim = CAKeyframeAnimation(keyPath: keyPath)
            anim.values = values
            anim.keyTimes = [0, 0.5, 1]
            anim.duration = configuration.period
            anim.repeatCount = .infinity
            anim.beginTime = CACurrentMediaTime() + Double(i) * configuration.period / spread
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(anim, forKey: "pulse")
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startAnimating() } else { stopAnimating() }
    }
}
