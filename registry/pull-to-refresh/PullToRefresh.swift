//
//  PullToRefresh.swift
//  Inlay — component
//
//  A custom, premium pull-to-refresh control you attach to any UIScrollView.
//  It replaces the system `UIRefreshControl` look with an interactive indicator
//  that draws on PROPORTIONALLY to how far you pull: a stroked circle that fills
//  0→1, a morphing shape that scales + rotates in, or a row of dots that grow.
//  Past the threshold + release, it enters a continuous "refreshing" animation,
//  fires a haptic, and calls your `onRefresh`. Call `endRefreshing()` when done.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `PullToRefresh.Configuration`.
//
//      let refresher = PullToRefresh()        // or PullToRefresh(configuration:)
//      refresher.attach(to: scrollView) { [weak self] in
//          self?.reload {                     // your async work
//              self?.refresher.endRefreshing()
//          }
//      }
//      // …and on teardown:
//      refresher.detach()
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class PullToRefresh: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Which indicator to draw on as the user pulls.
        var style: Style = .strokeCircle
        /// Tint for the indicator strokes / fills.
        var tintColor: UIColor = .tintColor
        /// Pull distance (points) required to arm a refresh.
        var threshold: CGFloat = 80
        /// Diameter of the indicator's drawing area.
        var indicatorSize: CGFloat = 30
        /// Stroke width for `.strokeCircle` and `.morphingShape`.
        var lineWidth: CGFloat = 3
        /// Spring used for arm/settle/end transitions. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Fire a haptic the instant the pull crosses the threshold.
        var hapticOnTrigger: Bool = true
        /// Keep the scroll inset held open (pinned) while refreshing so the
        /// indicator stays visible; otherwise it tucks under the content.
        var holdsInsetWhileRefreshing: Bool = true

        enum Style {
            /// A ring whose `strokeEnd` tracks pull distance, then spins.
            case strokeCircle
            /// A rounded square that scales + rotates in, then pulses + spins.
            case morphingShape
            /// A row of dots that grow in, then bounce in sequence.
            case bouncingDots
        }

        static let `default` = Configuration()
    }

    // MARK: - Public state

    /// `true` between the moment a refresh is triggered and `endRefreshing()`.
    private(set) var isRefreshing: Bool = false

    let configuration: Configuration

    // MARK: - Private state

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var onRefresh: (() -> Void)?

    /// The inset top that existed before we added our own, so we can restore it.
    private var baseInsetTop: CGFloat = 0
    /// Guards against the inset mutations we make re-entering the KVO handler.
    private var isMutatingInset = false

    /// 0…1 arming progress derived from pull distance.
    private var progress: CGFloat = 0

    // Indicator layers (only the ones for the active style are populated).
    private let ringTrackLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let morphLayer = CAShapeLayer()
    private var dotLayers: [CALayer] = []

    private let container = UIView()

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setup()
    }

    deinit {
        observation?.invalidate()
        observation = nil
    }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .clear

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        addSubview(container)

        let size = configuration.indicatorSize
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
        ])

        switch configuration.style {
        case .strokeCircle:  setupStrokeCircle()
        case .morphingShape: setupMorphingShape()
        case .bouncingDots:  setupBouncingDots()
        }

        updateProgress(0)
    }

    private func setupStrokeCircle() {
        let size = configuration.indicatorSize
        let lw = configuration.lineWidth
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: lw / 2, dy: lw / 2)
        let path = UIBezierPath(ovalIn: rect).cgPath

        for layer in [ringTrackLayer, ringLayer] {
            layer.path = path
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = lw
            layer.lineCap = .round
            layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
            container.layer.addSublayer(layer)
        }
        ringTrackLayer.strokeColor = configuration.tintColor.withAlphaComponent(0.18).cgColor
        ringLayer.strokeColor = configuration.tintColor.cgColor
        ringLayer.strokeEnd = 0
        // Start the stroke at the top of the ring.
        ringLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
    }

    private func setupMorphingShape() {
        let size = configuration.indicatorSize
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: configuration.lineWidth, dy: configuration.lineWidth)
        morphLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.28).cgPath
        morphLayer.fillColor = UIColor.clear.cgColor
        morphLayer.strokeColor = configuration.tintColor.cgColor
        morphLayer.lineWidth = configuration.lineWidth
        morphLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        container.layer.addSublayer(morphLayer)
    }

    private func setupBouncingDots() {
        let count = 3
        let size = configuration.indicatorSize
        let dotDiameter = size * 0.26
        let spacing = (size - dotDiameter) / CGFloat(count - 1)
        for i in 0..<count {
            let dot = CALayer()
            dot.backgroundColor = configuration.tintColor.cgColor
            dot.cornerRadius = dotDiameter / 2
            dot.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
            let x = dotDiameter / 2 + CGFloat(i) * spacing
            dot.position = CGPoint(x: x, y: size / 2)
            container.layer.addSublayer(dot)
            dotLayers.append(dot)
        }
    }

    // MARK: - Attach / detach

    /// Attach to a scroll view and start observing its `contentOffset`.
    /// The indicator positions itself just above the content.
    func attach(to scrollView: UIScrollView, onRefresh: @escaping () -> Void) {
        detach()

        self.scrollView = scrollView
        self.onRefresh = onRefresh
        self.baseInsetTop = scrollView.contentInset.top

        scrollView.addSubview(self)
        let size = configuration.indicatorSize
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            widthAnchor.constraint(equalToConstant: max(size, configuration.threshold)),
            heightAnchor.constraint(equalToConstant: max(size, configuration.threshold)),
            // Sit just above the content's top edge.
            bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        ])

        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            self?.scrollViewDidScroll(sv)
        }
    }

    /// Stop observing and tear down the inset/state. Safe to call repeatedly.
    func detach() {
        observation?.invalidate()
        observation = nil

        if isRefreshing { restoreInset(animated: false) }
        isRefreshing = false
        onRefresh = nil

        if superview != nil { removeFromSuperview() }
        scrollView = nil
    }

    // MARK: - Scroll handling

    private func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Ignore offset changes we cause ourselves while adjusting inset.
        guard !isMutatingInset else { return }

        let adjustedTop = scrollView.adjustedContentInset.top
        let pull = max(0, -(scrollView.contentOffset.y + adjustedTop))

        if isRefreshing {
            // While refreshing the indicator stays full; nothing to track.
            return
        }

        let threshold = configuration.threshold
        let newProgress = min(1, pull / threshold)
        updateProgress(newProgress)

        // Arm + fire on release: when the gesture lifts past the threshold.
        if pull >= threshold, !scrollView.isTracking, !scrollView.isDragging {
            beginRefreshing(in: scrollView)
        }
    }

    /// Map pull progress (0…1) onto the active indicator without animation.
    private func updateProgress(_ value: CGFloat) {
        progress = value

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch configuration.style {
        case .strokeCircle:
            ringLayer.strokeEnd = max(0.02, value)

        case .morphingShape:
            let scale = 0.4 + 0.6 * value
            let rotation = value * .pi
            morphLayer.opacity = Float(value)
            morphLayer.setAffineTransform(
                CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
            )

        case .bouncingDots:
            for (i, dot) in dotLayers.enumerated() {
                let stagger = CGFloat(i) * 0.18
                let local = max(0, min(1, (value - stagger) / (1 - stagger)))
                dot.opacity = Float(local)
                dot.setAffineTransform(CGAffineTransform(scaleX: local, y: local))
            }
        }

        CATransaction.commit()
    }

    // MARK: - Refresh lifecycle

    private func beginRefreshing(in scrollView: UIScrollView) {
        guard !isRefreshing else { return }
        isRefreshing = true

        if configuration.hapticOnTrigger {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        updateProgress(1)
        startContinuousAnimation()

        if configuration.holdsInsetWhileRefreshing {
            holdInset(in: scrollView)
        }

        onRefresh?()
    }

    /// Host calls this when its async work finishes.
    func endRefreshing(animated: Bool = true) {
        guard isRefreshing else { return }
        isRefreshing = false

        stopContinuousAnimation()
        restoreInset(animated: animated)

        if animated {
            Inlay.SpringAnimator.animate(configuration.animation) { [weak self] in
                self?.updateProgress(0)
            }
        } else {
            updateProgress(0)
        }
    }

    // MARK: - Inset management

    private func holdInset(in scrollView: UIScrollView) {
        let target = baseInsetTop + configuration.threshold
        isMutatingInset = true
        Inlay.SpringAnimator.animate(configuration.animation, animations: {
            scrollView.contentInset.top = target
        }, completion: { [weak self] in
            self?.isMutatingInset = false
        })
    }

    private func restoreInset(animated: Bool) {
        guard let scrollView = scrollView else { return }
        guard scrollView.contentInset.top != baseInsetTop else { return }

        isMutatingInset = true
        let apply = { scrollView.contentInset.top = self.baseInsetTop }
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, animations: apply,
                                         completion: { [weak self] in
                self?.isMutatingInset = false
            })
        } else {
            apply()
            isMutatingInset = false
        }
    }

    // MARK: - Continuous (refreshing) animation

    private static let spinKey = "inlay.ptr.spin"
    private static let pulseKey = "inlay.ptr.pulse"
    private static let bounceKey = "inlay.ptr.bounce"

    private func startContinuousAnimation() {
        switch configuration.style {
        case .strokeCircle:
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -CGFloat.pi / 2
            spin.toValue = -CGFloat.pi / 2 + 2 * .pi
            spin.duration = 0.9
            spin.repeatCount = .infinity
            ringLayer.add(spin, forKey: Self.spinKey)

        case .morphingShape:
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * CGFloat.pi
            spin.duration = 1.0
            spin.repeatCount = .infinity
            morphLayer.add(spin, forKey: Self.spinKey)

            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.85
            pulse.toValue = 1.0
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            morphLayer.add(pulse, forKey: Self.pulseKey)

        case .bouncingDots:
            for (i, dot) in dotLayers.enumerated() {
                let bounce = CABasicAnimation(keyPath: "transform.translation.y")
                bounce.fromValue = 0
                bounce.toValue = -configuration.indicatorSize * 0.3
                bounce.duration = 0.4
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.beginTime = CACurrentMediaTime() + Double(i) * 0.12
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(bounce, forKey: Self.bounceKey)
            }
        }
    }

    private func stopContinuousAnimation() {
        ringLayer.removeAnimation(forKey: Self.spinKey)
        morphLayer.removeAnimation(forKey: Self.spinKey)
        morphLayer.removeAnimation(forKey: Self.pulseKey)
        dotLayers.forEach { $0.removeAnimation(forKey: Self.bounceKey) }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep shape layers centered in the container as it lays out.
        let size = configuration.indicatorSize
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        ringTrackLayer.frame = frame
        ringLayer.frame = frame
        morphLayer.frame = frame
    }

    // MARK: - Dynamic color updates

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
        ringTrackLayer.strokeColor = configuration.tintColor.withAlphaComponent(0.18).cgColor
        ringLayer.strokeColor = configuration.tintColor.cgColor
        morphLayer.strokeColor = configuration.tintColor.cgColor
        dotLayers.forEach { $0.backgroundColor = configuration.tintColor.cgColor }
    }
}
