//
//  Toast.swift
//  Inlay — component
//
//  A transient notification banner that springs in from the top or bottom,
//  auto-dismisses, supports swipe-to-dismiss, drains a thin progress bar over
//  its lifetime, and stacks (rather than overlaps) when several are shown.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Present it with the static API — no need to keep a reference around.
//
//      Toast.show("Saved to your library", style: .success)
//
//      // Customised:
//      var config = Toast.Configuration.default
//      config.position = .bottom
//      config.duration = 4
//      config.background = .glass(.systemUltraThinMaterial)
//      Toast.show("Couldn't sync — tap to retry",
//                 style: .error,
//                 configuration: config,
//                 in: myView) // omit `in:` to present over the key window
//
//  Everything is customised through `Toast.Configuration`.
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class Toast: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {

        /// Semantic styles. Each picks a default SF Symbol + accent tint.
        enum Style {
            case info
            case success
            case warning
            case error

            /// Default SF Symbol shown when no explicit icon is passed.
            var symbolName: String {
                switch self {
                case .info:    return "info.circle.fill"
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error:   return "xmark.octagon.fill"
                }
            }

            /// Accent tint used for the icon and progress bar.
            var accent: UIColor {
                switch self {
                case .info:    return .systemBlue
                case .success: return .systemGreen
                case .warning: return .systemOrange
                case .error:   return .systemRed
                }
            }
        }

        /// Which edge the toast docks against and animates from.
        enum Position {
            case top
            case bottom
        }

        /// Background appearance of the toast surface.
        enum Background {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
        }

        /// Edge the toast docks against and springs in/out from.
        var position: Position = .top
        /// Seconds the toast stays on screen before auto-dismissing.
        var duration: TimeInterval = 3
        /// Corner radius of the toast surface.
        var cornerRadius: CGFloat = 18
        /// Background appearance.
        var background: Background = .glass(.systemThinMaterial)
        /// Whether the leading icon is shown.
        var showsIcon: Bool = true
        /// Whether the draining progress bar is shown.
        var showsProgressBar: Bool = true
        /// Whether a pan gesture can flick the toast away.
        var swipeToDismiss: Bool = true
        /// Haptic feedback on show (style-dependent).
        var hapticsEnabled: Bool = true
        /// Spring used for entrance, exit, and stack reflow. (Shared token.)
        var animation: Inlay.Spring = .lively
        /// Maximum width of the toast surface.
        var maxWidth: CGFloat = 460
        /// Padding from the safe-area edge and screen sides.
        var insets: UIEdgeInsets = .init(top: 12, left: 16, bottom: 12, right: 16)

        static let `default` = Configuration()
    }

    // MARK: - Static presentation API

    /// Currently on-screen toasts, newest last. Used for stacking + reflow.
    private static var active: [Toast] = []

    /// Present a toast. If `view` is nil it is added to the key window's safe
    /// area so it floats above whatever view controller is on screen.
    @discardableResult
    static func show(
        _ message: String,
        icon: UIImage? = nil,
        style: Configuration.Style = .info,
        configuration: Configuration = .default,
        in view: UIView? = nil
    ) -> Toast? {
        guard let host = view ?? Toast.hostWindow() else { return nil }

        let toast = Toast(
            message: message,
            icon: icon,
            style: style,
            configuration: configuration
        )
        host.addSubview(toast)
        toast.pin(to: host)
        active.append(toast)

        host.layoutIfNeeded()
        toast.fireHaptic()
        toast.restack(animated: false)   // place it off-screen at its slot
        toast.animateIn()
        return toast
    }

    /// Finds a sensible window to present over without a passed view.
    private static func hostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let scene = scenes.first ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
    }

    /// Re-lays the active stack so toasts offset instead of overlapping.
    private static func relayout(animated: Bool) {
        for toast in active { toast.restack(animated: animated) }
    }

    // MARK: - Private state

    private let configuration: Configuration
    private let style: Configuration.Style
    private let message: String
    private let icon: UIImage?

    private let container = UIView()
    private var backgroundView = UIView()
    private let iconView = UIImageView()
    private let label = UILabel()
    private let progressBar = UIView()

    private var edgeConstraint: NSLayoutConstraint?
    private var progressWidth: NSLayoutConstraint?

    private var dismissTimer: Timer?
    private var progressAnimator: UIViewPropertyAnimator?
    private var isDismissing = false
    private var stackOffset: CGFloat = 0

    // MARK: - Init

    private init(
        message: String,
        icon: UIImage?,
        style: Configuration.Style,
        configuration: Configuration
    ) {
        self.message = message
        self.icon = icon
        self.style = style
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("Toast is created through Toast.show(_:)")
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        setUpShadow()

        // Inner container clips the corner radius + background.
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

        setUpBackground()
        setUpContent()
        setUpProgressBar()
        setUpGestures()
    }

    private func setUpShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.20
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: 10)
    }

    private func setUpBackground() {
        switch configuration.background {
        case .glass(let style):
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .solid(let color):
            let view = UIView()
            view.backgroundColor = color
            backgroundView = view
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        container.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Hairline accent border for a premium edge in both color schemes.
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.withAlphaComponent(0.4).cgColor
    }

    private func setUpContent() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        if configuration.showsIcon {
            let symbolConfig = UIImage.SymbolConfiguration(
                pointSize: 20, weight: .semibold
            )
            iconView.image = (icon ?? UIImage(
                systemName: style.symbolName,
                withConfiguration: symbolConfig
            ))?.withConfiguration(symbolConfig)
            iconView.tintColor = style.accent
            iconView.contentMode = .scaleAspectFit
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(iconView)
        }

        label.text = message
        label.numberOfLines = 0
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func setUpProgressBar() {
        guard configuration.showsProgressBar else { return }
        progressBar.backgroundColor = style.accent
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer.cornerRadius = 1.5
        progressBar.layer.cornerCurve = .continuous
        container.addSubview(progressBar)

        // Progress bar sits along the inner edge (away from the docked edge).
        let edgeAnchor = configuration.position == .top
            ? progressBar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            : progressBar.topAnchor.constraint(equalTo: container.topAnchor)

        let width = progressBar.widthAnchor.constraint(
            equalTo: container.widthAnchor
        )
        progressWidth = width
        NSLayoutConstraint.activate([
            edgeAnchor,
            progressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 3),
            width,
        ])
    }

    private func setUpGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        if configuration.swipeToDismiss {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            addGestureRecognizer(pan)
        }
    }

    // MARK: - Layout

    /// Optional tap handler, run on tap before dismissing.
    var onTap: (() -> Void)?

    private func pin(to host: UIView) {
        let guide = host.safeAreaLayoutGuide
        let edge: NSLayoutConstraint
        switch configuration.position {
        case .top:
            edge = topAnchor.constraint(
                equalTo: guide.topAnchor, constant: configuration.insets.top
            )
        case .bottom:
            edge = bottomAnchor.constraint(
                equalTo: guide.bottomAnchor, constant: -configuration.insets.bottom
            )
        }
        edgeConstraint = edge

        let width = widthAnchor.constraint(lessThanOrEqualToConstant: configuration.maxWidth)
        width.priority = .required

        NSLayoutConstraint.activate([
            edge,
            centerXAnchor.constraint(equalTo: host.centerXAnchor),
            leadingAnchor.constraint(
                greaterThanOrEqualTo: guide.leadingAnchor,
                constant: configuration.insets.left
            ),
            trailingAnchor.constraint(
                lessThanOrEqualTo: guide.trailingAnchor,
                constant: -configuration.insets.right
            ),
            width,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the surface shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }

    // MARK: - Stacking

    /// Computes this toast's offset based on toasts ahead of it on the same
    /// edge, then animates the edge constraint to that slot.
    private func restack(animated: Bool) {
        guard let edge = edgeConstraint, let index = Toast.active.firstIndex(of: self)
        else { return }

        // Sum heights of toasts in front (closer to the edge) of this one.
        var offset: CGFloat = 0
        let ahead = Toast.active[..<index].filter {
            $0.configuration.position == configuration.position && !$0.isDismissing
        }
        for toast in ahead {
            offset += toast.bounds.height + 10
        }
        stackOffset = offset

        let base: CGFloat
        switch configuration.position {
        case .top:    base = configuration.insets.top + offset
        case .bottom: base = -(configuration.insets.bottom + offset)
        }
        edge.constant = base

        guard animated else {
            superview?.layoutIfNeeded()
            return
        }
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.superview?.layoutIfNeeded()
        }
    }

    // MARK: - Entrance / exit

    private func animateIn() {
        // Start off-screen on the docked edge.
        let host = superview
        host?.layoutIfNeeded()
        alpha = 0
        transform = offscreenTransform()

        Inlay.SpringAnimator.animate(configuration.animation, animations: {
            self.alpha = 1
            self.transform = .identity
        }, completion: { [weak self] in
            self?.startCountdown()
        })
    }

    private func offscreenTransform() -> CGAffineTransform {
        let distance = (bounds.height > 0 ? bounds.height : 80) + 60 + stackOffset
        switch configuration.position {
        case .top:    return CGAffineTransform(translationX: 0, y: -distance)
        case .bottom: return CGAffineTransform(translationX: 0, y: distance)
        }
    }

    private func startCountdown() {
        guard configuration.duration > 0 else { return }
        startProgressDrain()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.duration, repeats: false
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func startProgressDrain() {
        guard configuration.showsProgressBar, let width = progressWidth else { return }
        layoutIfNeeded()
        let animator = UIViewPropertyAnimator(
            duration: configuration.duration, curve: .linear
        ) { [weak self] in
            width.isActive = false
            self?.progressWidth = self?.progressBar.widthAnchor.constraint(equalToConstant: 0)
            self?.progressWidth?.isActive = true
            self?.layoutIfNeeded()
        }
        animator.startAnimation()
        progressAnimator = animator
    }

    /// Dismisses the toast: slides back out the docked edge while fading.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        dismissTimer?.invalidate()
        progressAnimator?.stopAnimation(true)

        Inlay.SpringAnimator.animate(configuration.animation, animations: {
            self.alpha = 0
            self.transform = self.offscreenTransform()
        }, completion: { [weak self] in
            self?.finishRemoval()
        })
    }

    private func finishRemoval() {
        removeFromSuperview()
        Toast.active.removeAll { $0 === self }
        Toast.relayout(animated: true)
    }

    // MARK: - Interaction

    @objc private func handleTap() {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onTap?()
        dismiss()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let host = superview else { return }
        let translation = gesture.translation(in: host)

        switch gesture.state {
        case .began, .changed:
            dismissTimer?.invalidate()
            progressAnimator?.pauseAnimation()
            // Resist dragging toward the screen, follow toward the edge.
            var dy = translation.y
            let towardEdge = configuration.position == .top ? dy < 0 : dy > 0
            if !towardEdge { dy *= 0.3 }
            transform = CGAffineTransform(translationX: 0, y: dy)
            let progress = min(abs(dy) / 120, 1)
            alpha = 1 - progress * 0.6

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: host).y
            let dy = translation.y
            let flicked = configuration.position == .top
                ? (dy < -50 || velocity < -600)
                : (dy > 50 || velocity > 600)
            if flicked {
                dismiss()
            } else {
                // Snap back and resume the countdown.
                Inlay.SpringAnimator.animate(configuration.animation) {
                    self.transform = .identity
                    self.alpha = 1
                }
                progressAnimator?.startAnimation()
                if configuration.duration > 0 {
                    let remaining = configuration.duration * Double(1 - (progressAnimator?.fractionComplete ?? 0))
                    dismissTimer = Timer.scheduledTimer(
                        withTimeInterval: max(remaining, 0.8), repeats: false
                    ) { [weak self] _ in self?.dismiss() }
                }
            }

        default:
            break
        }
    }

    // MARK: - Haptics

    private func fireHaptic() {
        guard configuration.hapticsEnabled else { return }
        switch style {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .info:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
