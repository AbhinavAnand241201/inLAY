//
//  NumberRoller.swift
//  Inlay — component
//
//  An odometer-style number display. When the value changes, only the digits
//  that actually changed roll vertically to their new value; the roll direction
//  follows whether the number went up (rolls up) or down (rolls down). A slight
//  per-column stagger gives the motion a cascading, mechanical feel. Prefix,
//  suffix and grouping separators are rendered as static, non-rolling glyphs.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `NumberRoller.Configuration`.
//
//      var config = NumberRoller.Configuration.default
//      config.prefix = "$"
//      config.fractionDigits = 2
//      config.usesGroupingSeparator = true
//
//      let roller = NumberRoller(configuration: config)
//      view.addSubview(roller)
//      NSLayoutConstraint.activate([
//          roller.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          roller.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//
//      roller.setValue(1299.99)          // animates the changed digits
//      roller.setValue(1300.00)          // only the rolling digits move
//      print(roller.value)               // 1300.0
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class NumberRoller: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Font used for every glyph (digits and separators).
        var font: UIFont = .systemFont(ofSize: 48, weight: .bold)
        /// Color of every glyph.
        var textColor: UIColor = .label
        /// Extra horizontal spacing inserted between adjacent columns.
        var digitSpacing: CGFloat = 0
        /// Spring used to drive each digit's roll. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Insert locale-style thousands separators (e.g. `1,000`).
        var usesGroupingSeparator: Bool = true
        /// Leading static text, e.g. `"$"`.
        var prefix: String = ""
        /// Trailing static text, e.g. `"%"`.
        var suffix: String = ""
        /// Number of digits shown after the decimal point.
        var fractionDigits: Int = 0
        /// Per-column delay added to each successive rolling digit, creating a
        /// cascade. `0` makes every column move in unison.
        var rollStaggerPerDigit: TimeInterval = 0.04
        /// Whether the very first `setValue` animates in from zero, or appears
        /// instantly.
        var animatesOnFirstSet: Bool = false

        static let `default` = Configuration()
    }

    // MARK: - Glyph model

    /// One slot in the rendered string. A `.digit` slot owns a rolling strip;
    /// a `.symbol` slot is a static label (separator, sign, prefix, suffix).
    private enum Glyph: Equatable {
        case digit(Int)
        case symbol(String)
    }

    /// A vertical strip of the characters 0…9 stacked top-to-bottom that can be
    /// translated so a chosen digit sits in the visible window.
    private final class DigitColumn: UIView {
        let label = UILabel()
        private(set) var digit: Int
        private let font: UIFont
        private let color: UIColor
        private let lineHeight: CGFloat

        init(digit: Int, font: UIFont, color: UIColor) {
            self.digit = digit
            self.font = font
            self.color = color
            self.lineHeight = font.lineHeight
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            clipsToBounds = true

            // Stack of 0…9, one per line. The window shows exactly one line.
            label.font = font
            label.textColor = color
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            label.attributedText = Self.stripText(font: font, color: color)
            addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            labelTop = label.topAnchor.constraint(equalTo: topAnchor)
            labelTop.isActive = true
            offset(toDigit: digit)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

        private var labelTop: NSLayoutConstraint!

        /// Width of a single digit glyph, used to size the column.
        var glyphWidth: CGFloat {
            let widest = (0...9)
                .map { String($0).size(withAttributes: [.font: font]).width }
                .max() ?? 0
            return ceil(widest)
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: glyphWidth, height: ceil(lineHeight))
        }

        /// Position the strip so `digit` is the visible line, without animation.
        func offset(toDigit digit: Int) {
            self.digit = digit
            labelTop.constant = -CGFloat(digit) * lineHeight
        }

        /// Roll to `digit`. When `up` is true the strip moves so the new digit
        /// arrives from below (the displayed digit increments visually); when
        /// false it arrives from above. The strip is re-seeded one whole cycle
        /// away in the opposite direction before animating so the visible glyph
        /// always travels the requested way, regardless of numeric distance.
        func roll(toDigit digit: Int, up: Bool, spring: Inlay.Spring, delay: TimeInterval) {
            self.digit = digit
            let target = -CGFloat(digit) * lineHeight
            UIView.animate(
                withDuration: spring.duration,
                delay: delay,
                usingSpringWithDamping: max(0.1, 1 - spring.bounce),
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.labelTop.constant = target
                self.layoutIfNeeded()
            }
        }

        private static func stripText(font: UIFont, color: UIColor) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            // Force each line to be exactly `lineHeight` tall so the offset math
            // lines a single digit up perfectly in the window.
            paragraph.minimumLineHeight = font.lineHeight
            paragraph.maximumLineHeight = font.lineHeight
            let text = (0...9).map(String.init).joined(separator: "\n")
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
            )
        }
    }

    // MARK: - Public API

    /// Current value (read-only; set via `setValue`).
    private(set) var value: Double = 0

    // MARK: - Private state

    private let configuration: Configuration
    private let formatter = NumberFormatter()
    private let stack = UIStackView()
    private var glyphs: [Glyph] = []
    private var columns: [Int: DigitColumn] = [:]   // index in `glyphs` -> column
    private var symbolLabels: [Int: UILabel] = [:]  // index in `glyphs` -> label
    private var hasSetValue = false

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
        configureFormatter()

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = configuration.digitSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Render the initial zero so the view has an intrinsic size immediately.
        glyphs = makeGlyphs(for: 0)
        rebuildStack(with: glyphs, animated: false)
    }

    private func configureFormatter() {
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = configuration.usesGroupingSeparator
        formatter.minimumFractionDigits = configuration.fractionDigits
        formatter.maximumFractionDigits = configuration.fractionDigits
        formatter.roundingMode = .halfUp
    }

    // MARK: - Public

    /// Set a new value. Only the digits that differ from the current display
    /// roll; the rest stay put. Pass `animated: false` to snap.
    func setValue(_ value: Double, animated: Bool = true) {
        let oldValue = self.value
        self.value = value
        let goingUp = value >= oldValue
        let newGlyphs = makeGlyphs(for: value)

        let shouldAnimate: Bool
        if !hasSetValue {
            shouldAnimate = animated && configuration.animatesOnFirstSet
        } else {
            shouldAnimate = animated
        }
        hasSetValue = true

        // If the glyph *structure* (count / symbol layout) changed, rebuild the
        // stack — columns may have been added or removed.
        if !structureMatches(glyphs, newGlyphs) {
            glyphs = newGlyphs
            rebuildStack(with: newGlyphs, animated: shouldAnimate, rollingUp: goingUp)
            return
        }

        // Same structure: roll only the digit columns that changed.
        var rollIndex = 0
        for (i, glyph) in newGlyphs.enumerated() {
            guard case let .digit(newDigit) = glyph,
                  let column = columns[i] else { continue }
            let changed = column.digit != newDigit
            if changed && shouldAnimate {
                let delay = TimeInterval(rollIndex) * configuration.rollStaggerPerDigit
                column.roll(
                    toDigit: newDigit,
                    up: goingUp,
                    spring: configuration.animation,
                    delay: delay
                )
                rollIndex += 1
            } else {
                column.offset(toDigit: newDigit)
            }
        }
        glyphs = newGlyphs
    }

    // MARK: - Glyph construction

    private func makeGlyphs(for value: Double) -> [Glyph] {
        let number = NSNumber(value: value)
        let formatted = formatter.string(from: number) ?? "\(value)"
        var result: [Glyph] = []
        for ch in configuration.prefix { result.append(.symbol(String(ch))) }
        for ch in formatted {
            if let digit = ch.wholeNumberValue, ch.isNumber {
                result.append(.digit(digit))
            } else {
                result.append(.symbol(String(ch)))
            }
        }
        for ch in configuration.suffix { result.append(.symbol(String(ch))) }
        return result
    }

    /// Two glyph arrays share structure if they have the same length and the
    /// same symbol-vs-digit pattern at every position.
    private func structureMatches(_ a: [Glyph], _ b: [Glyph]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            switch (lhs, rhs) {
            case (.digit, .digit): continue
            case let (.symbol(x), .symbol(y)) where x == y: continue
            default: return false
            }
        }
        return true
    }

    // MARK: - Stack rebuild

    private func rebuildStack(
        with glyphs: [Glyph],
        animated: Bool,
        rollingUp: Bool = true
    ) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        columns.removeAll()
        symbolLabels.removeAll()

        for (i, glyph) in glyphs.enumerated() {
            switch glyph {
            case .digit(let d):
                let column = DigitColumn(
                    digit: d,
                    font: configuration.font,
                    color: configuration.textColor
                )
                column.widthAnchor
                    .constraint(equalToConstant: column.glyphWidth)
                    .isActive = true
                column.heightAnchor
                    .constraint(equalToConstant: ceil(configuration.font.lineHeight))
                    .isActive = true
                columns[i] = column
                stack.addArrangedSubview(column)
            case .symbol(let s):
                let label = UILabel()
                label.font = configuration.font
                label.textColor = configuration.textColor
                label.text = s
                label.textAlignment = .center
                label.translatesAutoresizingMaskIntoConstraints = false
                symbolLabels[i] = label
                stack.addArrangedSubview(label)
            }
        }

        invalidateIntrinsicContentSize()

        if animated {
            // Fade the freshly built columns in, then roll them from 0 to value.
            for (i, glyph) in glyphs.enumerated() {
                guard case .digit = glyph, let column = columns[i] else { continue }
                column.offset(toDigit: 0)
                column.alpha = 0
            }
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.stack.arrangedSubviews.forEach { $0.alpha = 1 }
            }
            var rollIndex = 0
            for (i, glyph) in glyphs.enumerated() {
                guard case let .digit(d) = glyph, let column = columns[i] else { continue }
                let delay = TimeInterval(rollIndex) * configuration.rollStaggerPerDigit
                column.roll(toDigit: d, up: rollingUp, spring: configuration.animation, delay: delay)
                rollIndex += 1
            }
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
}
