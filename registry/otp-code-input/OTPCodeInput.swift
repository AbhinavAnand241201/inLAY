//
//  OTPCodeInput.swift
//  Inlay — component
//
//  A one-time-passcode (OTP) entry control: N individual boxes the user types a
//  code into. A single hidden text field drives all input, so it gets free SMS
//  autofill (`.oneTimeCode`), system paste, and backspace. The visible boxes
//  render the digits with a springy pop-in, an animated focus glow, and a
//  blinking caret. Call `shakeForError()` to reject a wrong code.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `OTPCodeInput.Configuration`.
//
//      let otp = OTPCodeInput()                     // 6 boxes, .box style
//      otp.onComplete = { code in
//          print("entered \(code)")
//          // if wrong: otp.shakeForError()
//      }
//      view.addSubview(otp)
//      NSLayoutConstraint.activate([
//          otp.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          otp.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class OTPCodeInput: UIControl {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Number of digit boxes.
        var length: Int = 6
        /// Size of each box.
        var boxSize: CGSize = CGSize(width: 48, height: 56)
        /// Gap between boxes.
        var spacing: CGFloat = 10
        /// Corner radius of a `.box`-style box.
        var cornerRadius: CGFloat = 12
        /// Font for the rendered digit.
        var font: UIFont = .systemFont(ofSize: 26, weight: .semibold)
        /// Box rendering style.
        var style: Style = .box
        /// Border (or underline) color when a box holds a digit.
        var filledBorderColor: UIColor = .label
        /// Border (or underline) color when a box is empty + unfocused.
        var emptyBorderColor: UIColor = .separator
        /// Border (or underline) color of the currently focused box.
        var focusedBorderColor: UIColor = .tintColor
        /// Color of the rendered digit / secure dot.
        var textColor: UIColor = .label
        /// Box fill color for `.box` style.
        var boxBackgroundColor: UIColor = .secondarySystemBackground
        /// Subtle tint laid under the focused box.
        var focusedBackgroundColor: UIColor = UIColor.tintColor.withAlphaComponent(0.08)
        /// Border width for `.box`; thickness of the rule for `.underline`.
        var borderWidth: CGFloat = 1.5
        /// Render dots instead of the actual digits.
        var isSecure: Bool = false
        /// Show a blinking caret in the focused, next-to-fill box.
        var showsCaret: Bool = true
        /// How much the focused box springs up (1.0 = no scale).
        var focusedScale: CGFloat = 1.08
        /// Spring used for pop-in / focus / shake recovery.
        var animation: Inlay.Spring = .playful
        /// Haptic feedback on each entry + on completion.
        var hapticsEnabled: Bool = true
        /// Wipe the code automatically after a `shakeForError()`.
        var clearsOnError: Bool = true

        enum Style {
            /// A bordered, filled rounded rectangle.
            case box
            /// A baseline underline only.
            case underline
        }

        static let `default` = Configuration()
    }

    // MARK: - Public API

    /// The current code. Setting it re-renders the boxes and fires `onChange`
    /// (and `onComplete` if it fills every box).
    var code: String {
        get { digits }
        set { setCode(newValue) }
    }

    /// Fires on every change to the entered digits.
    var onChange: ((String) -> Void)?

    /// Fires once all boxes are filled.
    var onComplete: ((String) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private var digits: String = "" {
        didSet { guard digits != oldValue else { return }; renderBoxes() }
    }

    private let textField = UITextField()
    private let stack = UIStackView()
    private var boxes: [BoxView] = []
    private var hasAppeared = false
    private let entryHaptic = UIImpactFeedbackGenerator(style: .light)
    private let completeHaptic = UINotificationFeedbackGenerator()

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

        setUpTextField()
        setUpStack()
        renderBoxes()
        prepareForEntrance()

        addTarget(self, action: #selector(handleSelfTap), for: .touchUpInside)
    }

    private func setUpTextField() {
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.tintColor = .clear            // hide the system caret
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.isHidden = false              // must be in hierarchy + visible to autofill
        textField.alpha = 0.02
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.widthAnchor.constraint(equalToConstant: 1),
            textField.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setUpStack() {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = configuration.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for _ in 0..<max(1, configuration.length) {
            let box = BoxView(configuration: configuration)
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: configuration.boxSize.width).isActive = true
            box.heightAnchor.constraint(equalToConstant: configuration.boxSize.height).isActive = true
            boxes.append(box)
            stack.addArrangedSubview(box)
        }
    }

    // MARK: - Code mutation

    private func setCode(_ raw: String) {
        let filtered = String(raw.filter(\.isNumber).prefix(configuration.length))
        guard filtered != digits else { return }
        textField.text = filtered
        digits = filtered
        onChange?(digits)
        if digits.count == configuration.length { fireComplete() }
    }

    private func fireComplete() {
        if configuration.hapticsEnabled { completeHaptic.notificationOccurred(.success) }
        onComplete?(digits)
    }

    @objc private func editingChanged() {
        // UITextField mutated (e.g. autofill / paste / delete) — sync state.
        let previousCount = digits.count
        let filtered = String((textField.text ?? "").filter(\.isNumber).prefix(configuration.length))
        if textField.text != filtered { textField.text = filtered }
        guard filtered != digits else { updateFocusState(); return }

        digits = filtered
        if configuration.hapticsEnabled, digits.count > previousCount {
            entryHaptic.impactOccurred()
        }
        onChange?(digits)
        updateFocusState()
        if digits.count == configuration.length { fireComplete() }
    }

    // MARK: - Rendering

    private func renderBoxes() {
        let chars = Array(digits)
        for (index, box) in boxes.enumerated() {
            let char: Character? = index < chars.count ? chars[index] : nil
            box.setCharacter(char, animated: hasAppeared)
        }
        updateFocusState()
    }

    private func updateFocusState() {
        let active = isFirstResponder
        let focusIndex = min(digits.count, boxes.count - 1)
        for (index, box) in boxes.enumerated() {
            let focused = active && index == focusIndex && digits.count < configuration.length
            box.setFocused(focused, caretEnabled: configuration.showsCaret)
        }
    }

    // MARK: - Focus / first responder

    @objc private func handleSelfTap() { becomeFirstResponder() }

    override var canBecomeFirstResponder: Bool { true }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let result = textField.becomeFirstResponder()
        updateFocusState()
        return result
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = textField.resignFirstResponder()
        updateFocusState()
        return result
    }

    override var isFirstResponder: Bool { textField.isFirstResponder }

    // Tapping anywhere in our bounds focuses the field.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.contains(point)
    }

    // MARK: - Error feedback

    /// Plays a horizontal shake, flashes every border red, then (optionally)
    /// clears the code.
    func shakeForError() {
        if configuration.hapticsEnabled { completeHaptic.notificationOccurred(.error) }
        boxes.forEach { $0.flashError() }

        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [-12, 12, -9, 9, -5, 5, 0]
        shake.keyTimes = [0, 0.16, 0.34, 0.5, 0.66, 0.84, 1]
        shake.duration = 0.5
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(shake, forKey: "inlay.otp.shake")

        guard configuration.clearsOnError else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            self.textField.text = ""
            self.digits = ""
            self.onChange?("")
            self.updateFocusState()
        }
    }

    // MARK: - Entrance animation

    private func prepareForEntrance() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
    }

    /// Plays the entrance once. Called automatically when added to a window.
    func playEntrance() {
        guard !hasAppeared else { return }
        hasAppeared = true
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.playEntrance() }
    }

    // MARK: - BoxView (nested)

    /// A single digit cell. Renders the character (or secure dot), the focus
    /// glow + scale, the blinking caret, and the error flash.
    private final class BoxView: UIView {
        private let configuration: Configuration
        private let label = UILabel()
        private let underline = UIView()
        private let caret = UIView()
        private var caretBlink: CAAnimation?
        private var character: Character?

        init(configuration: Configuration) {
            self.configuration = configuration
            super.init(frame: .zero)
            setUp()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        private func setUp() {
            layer.cornerRadius = configuration.cornerRadius
            layer.cornerCurve = .continuous

            switch configuration.style {
            case .box:
                backgroundColor = configuration.boxBackgroundColor
                layer.borderWidth = configuration.borderWidth
                layer.borderColor = configuration.emptyBorderColor.cgColor
            case .underline:
                backgroundColor = .clear
                underline.backgroundColor = configuration.emptyBorderColor
                underline.translatesAutoresizingMaskIntoConstraints = false
                addSubview(underline)
                NSLayoutConstraint.activate([
                    underline.leadingAnchor.constraint(equalTo: leadingAnchor),
                    underline.trailingAnchor.constraint(equalTo: trailingAnchor),
                    underline.bottomAnchor.constraint(equalTo: bottomAnchor),
                    underline.heightAnchor.constraint(equalToConstant: configuration.borderWidth),
                ])
            }

            label.font = configuration.font
            label.textColor = configuration.textColor
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])

            caret.backgroundColor = configuration.focusedBorderColor
            caret.layer.cornerRadius = 1
            caret.alpha = 0
            caret.translatesAutoresizingMaskIntoConstraints = false
            addSubview(caret)
            NSLayoutConstraint.activate([
                caret.centerXAnchor.constraint(equalTo: centerXAnchor),
                caret.centerYAnchor.constraint(equalTo: centerYAnchor),
                caret.widthAnchor.constraint(equalToConstant: 2),
                caret.heightAnchor.constraint(equalToConstant: configuration.font.lineHeight * 0.7),
            ])
        }

        // MARK: Character

        func setCharacter(_ char: Character?, animated: Bool) {
            let changed = char != character
            character = char
            if let char {
                label.text = configuration.isSecure ? "●" : String(char)
            } else {
                label.text = nil
            }
            applyBorder()

            guard changed, char != nil, animated else { return }
            // Digit pops in.
            label.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            label.alpha = 0
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.label.transform = .identity
                self.label.alpha = 1
            }
        }

        // MARK: Focus

        func setFocused(_ focused: Bool, caretEnabled: Bool) {
            applyBorder(focused: focused)

            let scale = focused ? configuration.focusedScale : 1.0
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
                if self.configuration.style == .box {
                    self.backgroundColor = focused
                        ? self.blend(self.configuration.boxBackgroundColor,
                                     over: self.configuration.focusedBackgroundColor)
                        : self.configuration.boxBackgroundColor
                }
            }

            if focused {
                applyGlow(true)
                if caretEnabled, character == nil { startCaret() } else { stopCaret() }
            } else {
                applyGlow(false)
                stopCaret()
            }
        }

        private func applyGlow(_ on: Bool) {
            layer.shadowColor = configuration.focusedBorderColor.cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = on ? 8 : 0
            let anim = CABasicAnimation(keyPath: "shadowOpacity")
            anim.fromValue = layer.shadowOpacity
            anim.toValue = on ? 0.5 : 0
            anim.duration = 0.25
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.shadowOpacity = on ? 0.5 : 0
            layer.add(anim, forKey: "inlay.otp.glow")
        }

        // MARK: Caret

        private func startCaret() {
            guard caretBlink == nil else { return }
            caret.alpha = 1
            let blink = CABasicAnimation(keyPath: "opacity")
            blink.fromValue = 1
            blink.toValue = 0
            blink.duration = 0.5
            blink.autoreverses = true
            blink.repeatCount = .infinity
            blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            caret.layer.add(blink, forKey: "inlay.otp.caret")
            caretBlink = blink
        }

        private func stopCaret() {
            caret.layer.removeAnimation(forKey: "inlay.otp.caret")
            caret.alpha = 0
            caretBlink = nil
        }

        // MARK: Borders

        private func applyBorder(focused: Bool = false) {
            let color: UIColor
            if focused {
                color = configuration.focusedBorderColor
            } else if character != nil {
                color = configuration.filledBorderColor
            } else {
                color = configuration.emptyBorderColor
            }
            switch configuration.style {
            case .box:
                layer.borderColor = color.cgColor
            case .underline:
                underline.backgroundColor = color
            }
        }

        // MARK: Error flash

        func flashError() {
            let red = UIColor.systemRed
            switch configuration.style {
            case .box:   layer.borderColor = red.cgColor
            case .underline: underline.backgroundColor = red
            }
            label.textColor = red

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.label.textColor = self.configuration.textColor
                self.applyBorder()
            }
        }

        // MARK: Helpers

        /// Composite `top` over `base` assuming `top` already carries its alpha.
        private func blend(_ base: UIColor, over top: UIColor) -> UIColor {
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            let a = ta
            return UIColor(
                red: tr * a + br * (1 - a),
                green: tg * a + bg * (1 - a),
                blue: tb * a + bb * (1 - a),
                alpha: 1
            )
        }
    }
}

// MARK: - UITextFieldDelegate

extension OTPCodeInput: UITextFieldDelegate {

    /// Handles single-digit typing, backspace, and full-code paste/autofill.
    /// We let the field mutate and reconcile in `editingChanged`, but we still
    /// filter to digits + length here so junk never lands in the field.
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        // Backspace.
        if string.isEmpty { return true }

        let current = textField.text ?? ""
        guard let stringRange = Range(range, in: current) else { return false }
        let updated = current.replacingCharacters(in: stringRange, with: string)
        let filtered = updated.filter(\.isNumber)

        // Reject pure non-digit input; accept (paste of) digits up to length.
        if filtered.isEmpty { return false }
        if filtered.count > configuration.length { return false }
        return string.allSatisfy(\.isNumber)
    }

    func textFieldDidBeginEditing(_ textField: UITextField) { updateFocusState() }
    func textFieldDidEndEditing(_ textField: UITextField) { updateFocusState() }
}
