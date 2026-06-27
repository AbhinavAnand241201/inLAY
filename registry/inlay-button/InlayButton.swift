//
//  InlayButton.swift
//  Inlay — component
//
//  A tactile, fully-programmatic button with four background styles
//  (glass / transparent / filled / soft) and three press effects
//  (scale / ripple / glow). Spring-driven feedback and a light haptic
//  on every completed tap.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `InlayButton.Configuration`.
//
//      var config = InlayButton.Configuration.default
//      config.style = .filled
//      config.pressEffect = .ripple
//
//      let button = InlayButton(
//          title: "Continue",
//          icon: UIImage(systemName: "arrow.right"),
//          configuration: config
//      ) {
//          print("tapped")
//      }
//      view.addSubview(button)
//      NSLayoutConstraint.activate([
//          button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class InlayButton: UIControl {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Background + border appearance.
        var style: Style = .filled
        /// Feedback shown while the button is pressed.
        var pressEffect: PressEffect = .scale
        /// Corner radius of the button.
        var cornerRadius: CGFloat = 14
        /// Drives the accent: fill, border, soft tint, and ripple/glow color.
        var accentColor: UIColor = .tintColor
        /// Spring used for press feedback. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Haptic feedback on a completed tap.
        var hapticsEnabled: Bool = true

        /// Background appearance.
        enum Style {
            /// `UIVisualEffectView` blur background.
            case glass(UIBlurEffect.Style)
            /// Clear background with a tinted border.
            case transparent
            /// Solid `accentColor` background, contrasting title color.
            case filled
            /// `accentColor` at a low alpha as a soft background.
            case soft
        }

        /// How the button reacts to a touch.
        enum PressEffect {
            /// Springs down to ~0.94 scale on touch-down, back on release.
            case scale
            /// Expanding circle from the touch point, clipped + fading out.
            case ripple
            /// A brief shadow opacity/radius pulse.
            case glow
        }

        static let `default` = Configuration()
    }

    // MARK: - Public

    /// Called on a completed tap (`.touchUpInside`).
    var onTap: () -> Void

    /// Update the visible title.
    var title: String? {
        didSet { titleLabel.text = title; updateLabelVisibility() }
    }

    /// Update the leading icon.
    var icon: UIImage? {
        didSet { iconView.image = icon; updateLabelVisibility() }
    }

    // MARK: - Private state

    private let configuration: Configuration

    // MARK: - Views

    /// Clips the corner radius and hosts the background + ripple.
    private let container = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let contentStack = UIStackView()
    private var blurView: UIVisualEffectView?

    // MARK: - Init

    init(
        title: String?,
        icon: UIImage? = nil,
        configuration: Configuration = .default,
        onTap: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onTap = onTap
        super.init(frame: .zero)
        self.title = title
        self.icon = icon
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — InlayButton is programmatic only.")
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // Outer view carries the shadow (used by the `.glow` press effect);
        // never clips so the glow can spread.
        layer.shadowColor = configuration.accentColor.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 0
        layer.shadowOpacity = 0

        // Inner container clips the corner radius.
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        container.layer.cornerRadius = configuration.cornerRadius
        container.layer.cornerCurve = .continuous
        addSubview(container)

        applyStyle()

        // Content.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = foregroundColor()
        iconView.image = icon
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            font: .preferredFont(forTextStyle: .headline)
        )

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = foregroundColor()
        titleLabel.textAlignment = .center

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.widthAnchor.constraint(lessThanOrEqualToConstant: 28),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        updateLabelVisibility()

        // Touch tracking via UIControl target-action.
        addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
        addTarget(self, action: #selector(handleTouchUpInside), for: .touchUpInside)
        addTarget(
            self,
            action: #selector(handleTouchRelease),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
    }

    // MARK: - Styling

    private func applyStyle() {
        // Clear any prior blur (in case style is re-applied).
        blurView?.removeFromSuperview()
        blurView = nil
        container.backgroundColor = .clear
        container.layer.borderWidth = 0
        container.layer.borderColor = nil

        switch configuration.style {
        case let .glass(blurStyle):
            let effect = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            effect.translatesAutoresizingMaskIntoConstraints = false
            effect.isUserInteractionEnabled = false
            container.insertSubview(effect, at: 0)
            NSLayoutConstraint.activate([
                effect.topAnchor.constraint(equalTo: container.topAnchor),
                effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            blurView = effect

        case .transparent:
            container.backgroundColor = .clear
            container.layer.borderWidth = 1.5
            container.layer.borderColor = configuration.accentColor.cgColor

        case .filled:
            container.backgroundColor = configuration.accentColor

        case .soft:
            container.backgroundColor = configuration.accentColor.withAlphaComponent(0.15)
        }
    }

    /// Color for title + icon, chosen to contrast with the chosen style.
    private func foregroundColor() -> UIColor {
        switch configuration.style {
        case .filled:
            // Contrasting title color over the accent fill.
            return .systemBackground
        case .glass:
            return .label
        case .transparent, .soft:
            return configuration.accentColor
        }
    }

    private func updateLabelVisibility() {
        titleLabel.isHidden = (title?.isEmpty ?? true)
        iconView.isHidden = (icon == nil)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the rounded shape for the `.glow` effect.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // Refresh resolved CGColors (border/shadow) for dark-mode switches.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            layer.shadowColor = configuration.accentColor.cgColor
            if case .transparent = configuration.style {
                container.layer.borderColor = configuration.accentColor.cgColor
            }
        }
    }

    // MARK: - Touch handling

    @objc private func handleTouchDown() {
        switch configuration.pressEffect {
        case .scale:
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            }
        case .ripple:
            // Origin at the live touch location, computed in `beginTracking`.
            emitRipple(at: lastTouchPoint)
        case .glow:
            startGlow()
        }
    }

    @objc private func handleTouchRelease() {
        switch configuration.pressEffect {
        case .scale:
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.transform = .identity
            }
        case .ripple:
            break // Ripple animates itself to completion.
        case .glow:
            endGlow()
        }
    }

    @objc private func handleTouchUpInside() {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onTap()
    }

    // Capture the touch point so the ripple originates where the user pressed.
    private var lastTouchPoint: CGPoint = .zero

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        lastTouchPoint = touch.location(in: container)
        return super.beginTracking(touch, with: event)
    }

    // MARK: - Ripple effect

    private func emitRipple(at point: CGPoint) {
        let ripple = CAShapeLayer()
        // Radius large enough to cover the whole button from any corner.
        let maxX = max(point.x, container.bounds.width - point.x)
        let maxY = max(point.y, container.bounds.height - point.y)
        let radius = (maxX * maxX + maxY * maxY).squareRoot()

        let startPath = UIBezierPath(
            arcCenter: point, radius: 0.01,
            startAngle: 0, endAngle: .pi * 2, clockwise: true
        ).cgPath
        let endPath = UIBezierPath(
            arcCenter: point, radius: radius,
            startAngle: 0, endAngle: .pi * 2, clockwise: true
        ).cgPath

        ripple.path = endPath
        ripple.fillColor = rippleColor().cgColor
        ripple.opacity = 0
        // Clipped to the container's rounded bounds.
        container.layer.addSublayer(ripple)

        let scale = CABasicAnimation(keyPath: "path")
        scale.fromValue = startPath
        scale.toValue = endPath

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.35, 0.0]
        fade.keyTimes = [0.0, 0.25, 1.0]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak ripple] in
            ripple?.removeFromSuperlayer()
        }
        ripple.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    private func rippleColor() -> UIColor {
        switch configuration.style {
        case .filled:
            return UIColor.systemBackground.withAlphaComponent(0.4)
        default:
            return configuration.accentColor.withAlphaComponent(0.35)
        }
    }

    // MARK: - Glow effect

    private func startGlow() {
        layer.shadowColor = configuration.accentColor.cgColor
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.layer.shadowOpacity = 0.7
            self.layer.shadowRadius = 14
        }
    }

    private func endGlow() {
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.layer.shadowOpacity = 0
            self.layer.shadowRadius = 0
        }
    }
}
