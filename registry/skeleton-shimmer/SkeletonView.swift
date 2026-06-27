//
//  SkeletonView.swift
//  Inlay — component
//
//  A loading-placeholder view that sweeps a soft highlight band across a base
//  color, with rounded corners. Use it to stand in for content that hasn't
//  loaded yet. The shimmer is a pure-Core-Animation gradient sweep, so it costs
//  almost nothing and keeps running smoothly off the main thread.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SkeletonView.Configuration`.
//
//      // A single rounded placeholder.
//      let avatar = SkeletonView()                 // auto-starts on screen
//      avatar.translatesAutoresizingMaskIntoConstraints = false
//      view.addSubview(avatar)
//      NSLayoutConstraint.activate([
//          avatar.widthAnchor.constraint(equalToConstant: 56),
//          avatar.heightAnchor.constraint(equalToConstant: 56),
//      ])
//
//      // A common list-cell placeholder: avatar + two lines of text.
//      let card = SkeletonView.card()
//      view.addSubview(card)
//
//      // A paragraph of placeholder text lines.
//      let para = SkeletonView.lines(3)
//      view.addSubview(para)
//
//  Dependency: none
//

import UIKit

final class SkeletonView: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Corner radius of the placeholder block. Use a large value (or set it
        /// to half the height) to read as a circle.
        var cornerRadius: CGFloat = 8
        /// The resting fill color shown beneath the moving highlight.
        var baseColor: UIColor = .secondarySystemFill
        /// The color of the sweeping highlight band.
        var highlightColor: UIColor = .systemFill
        /// Seconds for one full sweep of the highlight across the view.
        var shimmerDuration: CFTimeInterval = 1.4
        /// Pause between sweeps, in seconds. `0` loops continuously.
        var repeatDelay: CFTimeInterval = 0.25
        /// Direction the highlight travels.
        var direction: Direction = .leftToRight
        /// Width of the highlight band as a fraction of the sweep axis
        /// (0…1). Smaller reads as a tighter, brighter streak.
        var highlightWidth: CGFloat = 0.6
        /// Softness of the band's edges (0 = hard, 1 = fully feathered).
        var highlightSoftness: CGFloat = 1.0
        /// Begin shimmering automatically once the view reaches a window.
        var autoStarts: Bool = true

        /// Travel direction of the sweeping highlight.
        enum Direction {
            case leftToRight
            case rightToLeft
            case topToBottom
            case diagonal

            /// Start/end points for the gradient, expressed in unit space.
            fileprivate var points: (start: CGPoint, end: CGPoint) {
                switch self {
                case .leftToRight: return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
                case .rightToLeft: return (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
                case .topToBottom: return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
                case .diagonal:    return (CGPoint(x: 0, y: 0),   CGPoint(x: 1, y: 1))
                }
            }
        }

        /// Sensible defaults: a subtle, premium left-to-right sweep.
        static let `default` = Configuration()
    }

    // MARK: - Stored properties

    private(set) var configuration: Configuration
    private let gradientLayer = CAGradientLayer()
    private var isShimmering = false

    private static let shimmerKey = "inlay.skeleton.shimmer"

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — SkeletonView is programmatic.")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        applyAppearance()

        gradientLayer.actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull()]
        layer.addSublayer(gradientLayer)
        configureGradient()
    }

    // MARK: - Configuration application

    /// Apply a new configuration at runtime, restarting the shimmer if needed.
    func apply(_ configuration: Configuration) {
        let wasShimmering = isShimmering
        self.configuration = configuration
        applyAppearance()
        configureGradient()
        if wasShimmering { restart() }
    }

    private func applyAppearance() {
        layer.cornerRadius = configuration.cornerRadius
        backgroundColor = configuration.baseColor
    }

    private func configureGradient() {
        let points = configuration.direction.points
        gradientLayer.startPoint = points.start
        gradientLayer.endPoint = points.end

        // The band is the highlight color flanked by the (clear) base, so the
        // base color shows through everywhere except under the moving streak.
        let clear = configuration.highlightColor.withAlphaComponent(0).cgColor
        let solid = configuration.highlightColor.cgColor
        gradientLayer.colors = [clear, solid, clear]

        // Locations describe a band centered at 0.5; width + softness shape it.
        let half = max(0.001, min(0.5, configuration.highlightWidth / 2))
        let soft = max(0, min(1, configuration.highlightSoftness)) * half
        gradientLayer.locations = [
            NSNumber(value: Double(0.5 - half)),
            NSNumber(value: Double(0.5 - half + soft)),
            NSNumber(value: Double(0.5 + half)),
        ]
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        layer.cornerRadius = configuration.cornerRadius
    }

    // MARK: - Appearance changes (dark mode)

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            // CGColors don't resolve dynamic colors automatically; refresh them.
            applyAppearance()
            configureGradient()
        }
    }

    // MARK: - Window lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if configuration.autoStarts { startShimmering() }
        } else {
            // Tear down animation while off-screen to save work; remember state
            // so it resumes when re-attached.
            let resume = isShimmering
            stopShimmering()
            isShimmering = resume
        }
    }

    // MARK: - Shimmer control

    /// Start the sweeping highlight animation.
    func startShimmering() {
        isShimmering = true
        guard window != nil else { return } // resumes via didMoveToWindow
        gradientLayer.removeAnimation(forKey: Self.shimmerKey)
        gradientLayer.add(makeAnimation(), forKey: Self.shimmerKey)
    }

    /// Stop the animation and rest on the base color.
    func stopShimmering() {
        isShimmering = false
        gradientLayer.removeAnimation(forKey: Self.shimmerKey)
    }

    private func restart() {
        gradientLayer.removeAnimation(forKey: Self.shimmerKey)
        gradientLayer.add(makeAnimation(), forKey: Self.shimmerKey)
    }

    /// Build the sweep animation. The band's `locations` slide from fully before
    /// the leading edge to fully past the trailing edge, so it enters and exits
    /// cleanly. A non-zero `repeatDelay` wraps it in a group so the pause counts
    /// toward each cycle.
    private func makeAnimation() -> CAAnimation {
        let sweep = CABasicAnimation(keyPath: "locations")
        let half = max(0.001, min(0.5, configuration.highlightWidth / 2))
        let soft = max(0, min(1, configuration.highlightSoftness)) * half

        sweep.fromValue = [
            NSNumber(value: Double(-2 * half)),
            NSNumber(value: Double(-2 * half + soft)),
            NSNumber(value: Double(0.0)),
        ]
        sweep.toValue = [
            NSNumber(value: Double(1.0)),
            NSNumber(value: Double(1.0 + soft)),
            NSNumber(value: Double(1.0 + 2 * half)),
        ]
        sweep.duration = configuration.shimmerDuration
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        guard configuration.repeatDelay > 0 else {
            sweep.repeatCount = .infinity
            return sweep
        }

        let group = CAAnimationGroup()
        group.animations = [sweep]
        group.duration = configuration.shimmerDuration + configuration.repeatDelay
        group.repeatCount = .infinity
        return group
    }

    // MARK: - Composition builders

    /// A vertical stack of placeholder text lines. The last line is shortened
    /// to mimic a ragged paragraph end. All lines share one shimmer phase via
    /// the same duration so they read as a coherent block.
    ///
    ///     let paragraph = SkeletonView.lines(3)
    ///     view.addSubview(paragraph)
    static func lines(_ count: Int,
                      configuration: Configuration = .default,
                      lastLineFraction: CGFloat = 0.6,
                      lineHeight: CGFloat = 12,
                      spacing: CGFloat = 8) -> UIStackView {
        var lineConfig = configuration
        // Text lines read best as rounded pills.
        lineConfig.cornerRadius = min(configuration.cornerRadius, lineHeight / 2)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let total = max(0, count)
        for index in 0..<total {
            let isLast = index == total - 1
            let line = SkeletonView(configuration: lineConfig)
            line.heightAnchor.constraint(equalToConstant: lineHeight).isActive = true

            if isLast && total > 1 {
                // Shorten the last line using a width fraction wrapper row.
                let row = UIView()
                row.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(line)
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                    line.topAnchor.constraint(equalTo: row.topAnchor),
                    line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                    line.widthAnchor.constraint(equalTo: row.widthAnchor,
                                                multiplier: max(0.05, min(1, lastLineFraction))),
                ])
                stack.addArrangedSubview(row)
            } else {
                stack.addArrangedSubview(line)
            }
        }
        return stack
    }

    /// A common list-cell placeholder: a circular avatar beside two text lines.
    ///
    ///     let cell = SkeletonView.card()
    ///     view.addSubview(cell)
    static func card(configuration: Configuration = .default) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarSize: CGFloat = 48
        var avatarConfig = configuration
        avatarConfig.cornerRadius = avatarSize / 2
        let avatar = SkeletonView(configuration: avatarConfig)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: avatarSize),
            avatar.heightAnchor.constraint(equalToConstant: avatarSize),
        ])

        let titleLines = lines(2,
                               configuration: configuration,
                               lastLineFraction: 0.7,
                               lineHeight: 12,
                               spacing: 10)

        let row = UIStackView(arrangedSubviews: [avatar, titleLines])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
