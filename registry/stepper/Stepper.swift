//
//  Stepper.swift
//  Inlay — component
//
//  A premium − [value] + stepper. The value ROLLS vertically when it changes:
//  the old number slides out and the new one springs in, with the roll
//  direction following increase vs decrease. The +/− buttons scale on press,
//  fade out when min/max is reached, and support long-press repeat with
//  acceleration.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `Stepper.Configuration`.
//
//      var config = Stepper.Configuration.default
//      config.minimumValue = 0
//      config.maximumValue = 10
//      config.step = 1
//      config.style = .pill
//
//      let stepper = Stepper(configuration: config)
//      stepper.onChange = { value in print("value:", value) }
//      view.addSubview(stepper)
//      NSLayoutConstraint.activate([
//          stepper.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          stepper.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class Stepper: UIControl {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Starting value. Clamped into `minimumValue...maximumValue`.
        var value: Double = 0
        /// Lowest reachable value.
        var minimumValue: Double = 0
        /// Highest reachable value.
        var maximumValue: Double = 100
        /// Amount added/removed per tap.
        var step: Double = 1
        /// Turns a value into display text. Default trims a trailing `.0`.
        var valueFormatter: (Double) -> String = Stepper.defaultFormatter
        /// Tint for the +/− glyphs (and pill-style controls).
        var tintColor: UIColor = .label
        /// Background fill of the control surface.
        var backgroundColorValue: UIColor = .secondarySystemBackground
        /// Corner radius of the surface(s).
        var cornerRadius: CGFloat = 16
        /// Visual arrangement.
        var style: Style = .pill
        /// Edge length of each square button.
        var buttonSize: CGFloat = 44
        /// Font of the rolling value label.
        var font: UIFont = .systemFont(ofSize: 18, weight: .semibold)
        /// Spring used for the roll + press feedback. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Haptic feedback on each step.
        var hapticsEnabled: Bool = true
        /// Whether holding +/− repeats (and accelerates).
        var allowsLongPressRepeat: Bool = true

        /// `.pill`  — one rounded capsule: − value +
        /// `.split` — two separate buttons flanking a detached value chip.
        enum Style {
            case pill
            case split
        }

        static let `default` = Configuration()
    }

    // MARK: - Public API

    /// The current value. Setting this animates the roll and notifies
    /// `onChange`. Always clamped into the configured range.
    var value: Double {
        get { _value }
        set { setValue(newValue, animated: true, notify: true) }
    }

    /// Set the value without firing `onChange` (e.g. external sync).
    func setValue(_ newValue: Double, animated: Bool) {
        setValue(newValue, animated: animated, notify: false)
    }

    /// Called whenever the value changes via user interaction or `value =`.
    var onChange: ((Double) -> Void)?

    // MARK: - Roll direction

    private enum RollDirection { case up, down }

    // MARK: - Private state

    private let configuration: Configuration
    private var _value: Double

    private let minusButton = UIButton(type: .custom)
    private let plusButton = UIButton(type: .custom)

    /// The framed, clipped window the rolling labels live in.
    private let valueClip = UIView()
    private var currentLabel = UILabel()
    private let valueChip = UIView()        // used by `.split`
    private let pillBackground = UIView()   // used by `.pill`

    private var minusEnabledValue = true
    private var plusEnabledValue = true

    // Long-press repeat.
    private var repeatTimer: Timer?
    private var repeatStep: Double = 0
    private var repeatTickCount = 0
    private var repeatInterval: TimeInterval = 0.32

    private lazy var impact = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self._value = Stepper.clamp(configuration.value, configuration)
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self._value = 0
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        switch configuration.style {
        case .pill:  setUpPill()
        case .split: setUpSplit()
        }

        configureButton(minusButton, symbol: "minus")
        configureButton(plusButton, symbol: "plus")

        setUpValueLabel()
        updateButtonAvailability(animated: false)
    }

    private func setUpPill() {
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.backgroundColor = configuration.backgroundColorValue
        pillBackground.layer.cornerRadius = configuration.cornerRadius
        pillBackground.layer.cornerCurve = .continuous
        pillBackground.clipsToBounds = true
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)

        valueClip.translatesAutoresizingMaskIntoConstraints = false
        valueClip.clipsToBounds = true
        valueClip.isUserInteractionEnabled = false

        addSubview(minusButton)
        addSubview(valueClip)
        addSubview(plusButton)

        let h = configuration.buttonSize
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: h),

            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),

            minusButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            minusButton.topAnchor.constraint(equalTo: topAnchor),
            minusButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            minusButton.widthAnchor.constraint(equalToConstant: h),

            valueClip.leadingAnchor.constraint(equalTo: minusButton.trailingAnchor),
            valueClip.topAnchor.constraint(equalTo: topAnchor),
            valueClip.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueClip.widthAnchor.constraint(greaterThanOrEqualToConstant: h),

            plusButton.leadingAnchor.constraint(equalTo: valueClip.trailingAnchor),
            plusButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            plusButton.topAnchor.constraint(equalTo: topAnchor),
            plusButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: h),
        ])
    }

    private func setUpSplit() {
        let spacing: CGFloat = 8
        let h = configuration.buttonSize

        for surface in [minusButton, valueChip, plusButton] {
            surface.translatesAutoresizingMaskIntoConstraints = false
        }

        minusButton.backgroundColor = configuration.backgroundColorValue
        plusButton.backgroundColor = configuration.backgroundColorValue
        for b in [minusButton, plusButton] {
            b.layer.cornerRadius = configuration.cornerRadius
            b.layer.cornerCurve = .continuous
            b.clipsToBounds = true
        }

        valueChip.backgroundColor = configuration.backgroundColorValue
        valueChip.layer.cornerRadius = configuration.cornerRadius
        valueChip.layer.cornerCurve = .continuous
        valueChip.clipsToBounds = true
        valueChip.isUserInteractionEnabled = false

        valueClip.translatesAutoresizingMaskIntoConstraints = false
        valueClip.clipsToBounds = true
        valueClip.isUserInteractionEnabled = false
        valueChip.addSubview(valueClip)

        addSubview(minusButton)
        addSubview(valueChip)
        addSubview(plusButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: h),

            minusButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            minusButton.topAnchor.constraint(equalTo: topAnchor),
            minusButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            minusButton.widthAnchor.constraint(equalToConstant: h),

            valueChip.leadingAnchor.constraint(equalTo: minusButton.trailingAnchor, constant: spacing),
            valueChip.topAnchor.constraint(equalTo: topAnchor),
            valueChip.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueChip.widthAnchor.constraint(greaterThanOrEqualToConstant: h * 1.4),

            valueClip.topAnchor.constraint(equalTo: valueChip.topAnchor),
            valueClip.bottomAnchor.constraint(equalTo: valueChip.bottomAnchor),
            valueClip.leadingAnchor.constraint(equalTo: valueChip.leadingAnchor),
            valueClip.trailingAnchor.constraint(equalTo: valueChip.trailingAnchor),

            plusButton.leadingAnchor.constraint(equalTo: valueChip.trailingAnchor, constant: spacing),
            plusButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            plusButton.topAnchor.constraint(equalTo: topAnchor),
            plusButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: h),
        ])
    }

    private func configureButton(_ button: UIButton, symbol: String) {
        let weight = UIImage.SymbolConfiguration(weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: weight), for: .normal)
        button.tintColor = configuration.tintColor

        let isMinus = (symbol == "minus")
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUp(_:)),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.addAction(UIAction { [weak self] _ in
            self?.handleTap(increment: !isMinus)
        }, for: .touchUpInside)

        if configuration.allowsLongPressRepeat {
            let press = UILongPressGestureRecognizer(
                target: self,
                action: isMinus ? #selector(minusLongPress(_:)) : #selector(plusLongPress(_:))
            )
            press.minimumPressDuration = 0.3
            button.addGestureRecognizer(press)
        }
    }

    private func setUpValueLabel() {
        styleValueLabel(currentLabel)
        valueClip.addSubview(currentLabel)
        currentLabel.frame = valueClip.bounds
        currentLabel.text = configuration.valueFormatter(_value)
    }

    private func styleValueLabel(_ label: UILabel) {
        label.font = configuration.font
        label.textColor = configuration.tintColor
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the (frame-based) rolling label sized to its clip window.
        currentLabel.frame = valueClip.bounds
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: configuration.buttonSize)
    }

    // MARK: - Interaction

    private func handleTap(increment: Bool) {
        let delta = increment ? configuration.step : -configuration.step
        let next = Stepper.clamp(_value + delta, configuration)
        guard next != _value else { return }
        setValue(next, animated: true, notify: true)
    }

    @objc private func buttonTouchDown(_ sender: UIButton) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        }
    }

    @objc private func buttonTouchUp(_ sender: UIButton) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = .identity
        }
    }

    // MARK: - Long-press repeat

    @objc private func minusLongPress(_ g: UILongPressGestureRecognizer) {
        handleLongPress(g, increment: false)
    }

    @objc private func plusLongPress(_ g: UILongPressGestureRecognizer) {
        handleLongPress(g, increment: true)
    }

    private func handleLongPress(_ g: UILongPressGestureRecognizer, increment: Bool) {
        switch g.state {
        case .began:
            beginRepeat(increment: increment)
        case .ended, .cancelled, .failed:
            stopRepeat()
        default:
            break
        }
    }

    private func beginRepeat(increment: Bool) {
        stopRepeat()
        repeatStep = increment ? configuration.step : -configuration.step
        repeatTickCount = 0
        repeatInterval = 0.32
        // First repeat tick fires immediately for responsiveness.
        repeatTick()
        scheduleRepeatTimer()
    }

    private func scheduleRepeatTimer() {
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: repeatInterval, repeats: false) { [weak self] _ in
            self?.repeatTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func repeatTick() {
        let next = Stepper.clamp(_value + repeatStep, configuration)
        if next != _value {
            setValue(next, animated: true, notify: true)
            repeatTickCount += 1
            // Accelerate: shrink the interval over time, floored at 0.05s.
            repeatInterval = max(0.05, 0.32 * pow(0.82, Double(repeatTickCount)))
            scheduleRepeatTimer()
        } else {
            // Hit the boundary — stop repeating (the button will fade out).
            stopRepeat()
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: - Value & rolling animation

    private func setValue(_ raw: Double, animated: Bool, notify: Bool) {
        let clamped = Stepper.clamp(raw, configuration)
        guard clamped != _value else {
            updateButtonAvailability(animated: animated)
            return
        }
        let direction: RollDirection = clamped > _value ? .up : .down
        _value = clamped

        if configuration.hapticsEnabled {
            impact.impactOccurred()
            impact.prepare()
        }

        let text = configuration.valueFormatter(_value)
        if animated {
            rollValue(to: text, direction: direction)
        } else {
            currentLabel.text = text
        }

        updateButtonAvailability(animated: animated)

        if notify {
            onChange?(_value)
            sendActions(for: .valueChanged)
        }
    }

    /// Slides the old label out and a fresh label in, springing into place.
    /// Increase rolls upward (new enters from below); decrease rolls downward.
    private func rollValue(to text: String, direction: RollDirection) {
        valueClip.layoutIfNeeded()
        let height = valueClip.bounds.height
        guard height > 0 else { currentLabel.text = text; return }

        let outgoing = currentLabel
        let incoming = UILabel()
        styleValueLabel(incoming)
        incoming.text = text
        incoming.frame = valueClip.bounds

        // New label starts off-window on the side it rolls in from.
        let enterOffset = direction == .up ? height : -height
        incoming.transform = CGAffineTransform(translationX: 0, y: enterOffset)
        incoming.alpha = 0
        valueClip.addSubview(incoming)
        currentLabel = incoming

        let exitOffset = direction == .up ? -height : height
        Inlay.SpringAnimator.animate(configuration.animation, animations: {
            incoming.transform = .identity
            incoming.alpha = 1
            outgoing.transform = CGAffineTransform(translationX: 0, y: exitOffset)
            outgoing.alpha = 0
        }, completion: {
            outgoing.removeFromSuperview()
        })
    }

    // MARK: - Button availability

    private func updateButtonAvailability(animated: Bool) {
        let canDecrease = _value > configuration.minimumValue
        let canIncrease = _value < configuration.maximumValue

        if canDecrease != minusEnabledValue {
            minusEnabledValue = canDecrease
            setButton(minusButton, enabled: canDecrease, animated: animated)
            if !canDecrease { stopRepeat() }
        }
        if canIncrease != plusEnabledValue {
            plusEnabledValue = canIncrease
            setButton(plusButton, enabled: canIncrease, animated: animated)
            if !canIncrease { stopRepeat() }
        }
    }

    private func setButton(_ button: UIButton, enabled: Bool, animated: Bool) {
        button.isEnabled = enabled
        let targetAlpha: CGFloat = enabled ? 1 : 0.25
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation) {
                button.alpha = targetAlpha
            }
        } else {
            button.alpha = targetAlpha
        }
    }

    // MARK: - Helpers

    private static func clamp(_ v: Double, _ c: Configuration) -> Double {
        min(max(v, c.minimumValue), c.maximumValue)
    }

    /// Default formatter: integers drop the trailing `.0`, otherwise up to two
    /// decimals are shown.
    private static func defaultFormatter(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
