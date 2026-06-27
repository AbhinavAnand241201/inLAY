//
//  RatingView.swift
//  Inlay — component
//
//  An interactive star (or custom symbol) rating control. Tap a star or drag
//  horizontally across the row to set the value live. Each star pops with a
//  spring overshoot as it fills, and half-ratings are rendered with a
//  fractional fill mask. A light haptic ticks as the rating changes.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `RatingView.Configuration`.
//
//      let rating = RatingView()
//      rating.onChange = { value in print("rated \(value)") }
//      rating.rating = 3.5            // settable → animates
//      view.addSubview(rating)
//      NSLayoutConstraint.activate([
//          rating.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          rating.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//      // Display-only, half-ratings, custom symbol:
//      var config = RatingView.Configuration.default
//      config.isInteractive = false
//      config.allowsHalfRatings = true
//      config.symbol = UIImage(systemName: "heart.fill")!
//      let display = RatingView(configuration: config)
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class RatingView: UIControl {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Number of stars in the row.
        var maximumRating: Int = 5
        /// When `true`, drag/tap snaps to the nearest half; otherwise whole.
        var allowsHalfRatings: Bool = false
        /// The filled symbol (also the empty silhouette when `emptySymbol` is nil).
        var symbol: UIImage = UIImage(systemName: "star.fill") ?? UIImage()
        /// Optional distinct empty-state symbol (e.g. "star"). Nil → `symbol`
        /// rendered in `emptyColor`.
        var emptySymbol: UIImage? = nil
        /// Tint of the filled portion.
        var filledColor: UIColor = .systemYellow
        /// Tint of the empty portion.
        var emptyColor: UIColor = .tertiaryLabel
        /// Side length of each star (points).
        var starSize: CGFloat = 36
        /// Gap between stars (points).
        var spacing: CGFloat = 6
        /// Spring used for fill + pop. (Shared design token.)
        var animation: Inlay.Spring = .playful
        /// Light haptic tick as the rating crosses to a new value.
        var hapticsEnabled: Bool = true
        /// When `false` the control is display-only (no tap/drag).
        var isInteractive: Bool = true

        static let `default` = Configuration()
    }

    // MARK: - Star

    /// One star slot: an empty silhouette plus a filled overlay clipped by a
    /// mask whose width tracks the fill fraction (0...1).
    private final class Star: UIView {
        let emptyImageView = UIImageView()
        let filledImageView = UIImageView()
        private let fillMask = CALayer()
        private(set) var fillFraction: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            translatesAutoresizingMaskIntoConstraints = false
            isUserInteractionEnabled = false

            emptyImageView.contentMode = .scaleAspectFit
            filledImageView.contentMode = .scaleAspectFit
            emptyImageView.translatesAutoresizingMaskIntoConstraints = false
            filledImageView.translatesAutoresizingMaskIntoConstraints = false

            // The mask is a solid block; we resize its width to clip the fill.
            fillMask.backgroundColor = UIColor.black.cgColor
            filledImageView.layer.mask = fillMask

            addSubview(emptyImageView)
            addSubview(filledImageView)
            NSLayoutConstraint.activate([
                emptyImageView.topAnchor.constraint(equalTo: topAnchor),
                emptyImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
                emptyImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                emptyImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                filledImageView.topAnchor.constraint(equalTo: topAnchor),
                filledImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
                filledImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                filledImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func setFill(_ fraction: CGFloat) {
            fillFraction = max(0, min(1, fraction))
            applyMask()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyMask()
        }

        private func applyMask() {
            // Mask layers ignore implicit animation here so the fill snaps
            // crisply while the surrounding view springs.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillMask.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width * fillFraction,
                height: bounds.height
            )
            CATransaction.commit()
        }
    }

    // MARK: - Public API

    /// The current rating. Setting it animates the fills + pops.
    var rating: Double {
        get { _rating }
        set { setRating(newValue, animated: true, notify: false) }
    }

    /// Called whenever the rating changes via interaction or `rating` setter.
    var onChange: ((Double) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private var _rating: Double = 0
    private var stars: [Star] = []
    private let stack = UIStackView()
    private lazy var haptics = UISelectionFeedbackGenerator()

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

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = configuration.spacing
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let count = max(1, configuration.maximumRating)
        let emptyImage = (configuration.emptySymbol ?? configuration.symbol)
            .withRenderingMode(.alwaysTemplate)
        let filledImage = configuration.symbol.withRenderingMode(.alwaysTemplate)

        for _ in 0..<count {
            let star = Star()
            star.emptyImageView.image = emptyImage
            star.emptyImageView.tintColor = configuration.emptyColor
            star.filledImageView.image = filledImage
            star.filledImageView.tintColor = configuration.filledColor
            star.widthAnchor.constraint(equalToConstant: configuration.starSize).isActive = true
            star.heightAnchor.constraint(equalToConstant: configuration.starSize).isActive = true
            stars.append(star)
            stack.addArrangedSubview(star)
        }

        if configuration.isInteractive {
            isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            addGestureRecognizer(tap)
            addGestureRecognizer(pan)
            isAccessibilityElement = true
            accessibilityTraits = .adjustable
        } else {
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityTraits = .staticText
        }

        applyFills(animated: false, poppingNewlyFilled: false, previousRating: 0)
        updateAccessibilityValue()
    }

    // MARK: - Interaction

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let value = rating(atX: gesture.location(in: self).x)
        setRating(value, animated: true, notify: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            haptics.prepare()
            fallthrough
        case .changed, .ended:
            let value = rating(atX: gesture.location(in: self).x)
            setRating(value, animated: gesture.state != .changed, notify: true)
        default:
            break
        }
    }

    /// Maps an x position in the control to a rating, snapping per config.
    private func rating(atX x: CGFloat) -> Double {
        let count = stars.count
        guard count > 0 else { return 0 }
        let step = configuration.starSize + configuration.spacing
        // Progress through the row, ignoring trailing spacing past the last star.
        let raw = Double(x / step)
        if configuration.allowsHalfRatings {
            // Round to the nearest half-star, but bias so the left half of a
            // star reads as a half and the right half as a whole.
            let halves = (raw * 2).rounded(.up)
            return min(max(halves / 2, 0), Double(count))
        } else {
            let whole = raw.rounded(.up)
            return min(max(whole, 0), Double(count))
        }
    }

    // MARK: - Rating application

    private func setRating(_ value: Double, animated: Bool, notify: Bool) {
        let clamped = min(max(value, 0), Double(stars.count))
        let snapped = snap(clamped)
        let previous = _rating
        let changed = snapped != previous
        _rating = snapped

        if changed && configuration.hapticsEnabled {
            haptics.selectionChanged()
            haptics.prepare()
        }

        applyFills(
            animated: animated,
            poppingNewlyFilled: changed,
            previousRating: previous
        )
        updateAccessibilityValue()

        if notify && changed {
            onChange?(snapped)
            sendActions(for: .valueChanged)
        }
    }

    private func snap(_ value: Double) -> Double {
        if configuration.allowsHalfRatings {
            return (value * 2).rounded() / 2
        } else {
            return value.rounded()
        }
    }

    /// Updates every star's fill fraction and pops any star that crossed the
    /// fill threshold since the previous rating.
    private func applyFills(animated: Bool, poppingNewlyFilled: Bool, previousRating: Double) {
        for (index, star) in stars.enumerated() {
            let lowerBound = Double(index)
            let fraction = CGFloat(min(max(_rating - lowerBound, 0), 1))

            let didGain = fraction > star.fillFraction
            let apply = { star.setFill(fraction) }

            if animated {
                Inlay.SpringAnimator.animate(configuration.animation, apply)
            } else {
                apply()
            }

            if poppingNewlyFilled && didGain {
                pop(star)
            }
        }
    }

    /// Spring scale overshoot on a star as it becomes (more) filled.
    private func pop(_ star: Star) {
        star.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        Inlay.SpringAnimator.animate(configuration.animation) {
            star.transform = .identity
        }
    }

    // MARK: - Accessibility

    private func updateAccessibilityValue() {
        accessibilityLabel = "Rating"
        let formatted = _rating == _rating.rounded()
            ? String(Int(_rating))
            : String(_rating)
        accessibilityValue = "\(formatted) of \(stars.count)"
    }

    override func accessibilityIncrement() {
        let step = configuration.allowsHalfRatings ? 0.5 : 1.0
        setRating(_rating + step, animated: true, notify: true)
    }

    override func accessibilityDecrement() {
        let step = configuration.allowsHalfRatings ? 0.5 : 1.0
        setRating(_rating - step, animated: true, notify: true)
    }

    // MARK: - Sizing

    override var intrinsicContentSize: CGSize {
        let count = CGFloat(stars.count)
        let width = count * configuration.starSize + max(0, count - 1) * configuration.spacing
        return CGSize(width: width, height: configuration.starSize)
    }
}
