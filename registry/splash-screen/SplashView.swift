//
//  SplashView.swift
//  Inlay — component
//
//  A generic launch / splash animation built from a single letter. Drop it in
//  full-screen at app start, give it your brand initial, and it animates the
//  letter in on appearance, then fires `onFinish` so you can transition away.
//
//  Three entrance styles are available via `Configuration.entrance`:
//    .fadeScale  — the letter fades + springs up from a smaller scale.
//    .strokeDraw — the glyph outline is "written" by animating a stroke.
//    .maskReveal — a solid fill is revealed through the glyph, scaling up.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SplashView.Configuration`.
//
//      let splash = SplashView(letter: "I")
//      splash.onFinish = { splash.removeFromSuperview() }
//      splash.frame = view.bounds
//      splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//      view.addSubview(splash)   // auto-plays once it has a window
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit
import CoreText

final class SplashView: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {

        /// The entrance animation style.
        enum Entrance {
            /// A UILabel with the letter fades + springs up from ~0.6 scale.
            case fadeScale
            /// Animate a stroke 0→1 to "write" the letter outline.
            case strokeDraw
            /// Reveal a solid fill through the glyph, scaling it up.
            case maskReveal
        }

        /// Font used to render / shape the letter.
        var font: UIFont = SplashView.defaultFont
        /// Color of the letter (fill for fadeScale/maskReveal, stroke for draw).
        var textColor: UIColor = .label
        /// Background color behind the letter.
        var backgroundColorValue: UIColor = .systemBackground
        /// Total animation duration.
        var duration: TimeInterval = 1.0
        /// The entrance style.
        var entrance: Entrance = .fadeScale

        static let `default` = Configuration()

        init(
            font: UIFont = SplashView.defaultFont,
            textColor: UIColor = .label,
            backgroundColorValue: UIColor = .systemBackground,
            duration: TimeInterval = 1.0,
            entrance: Entrance = .fadeScale
        ) {
            self.font = font
            self.textColor = textColor
            self.backgroundColorValue = backgroundColorValue
            self.duration = duration
            self.entrance = entrance
        }
    }

    /// A heavy, rounded system font when available (falls back gracefully).
    static var defaultFont: UIFont {
        let base = UIFont.systemFont(ofSize: 120, weight: .heavy)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: 120)
        }
        return base
    }

    // MARK: - Public

    /// Fires once, after the entrance animation completes.
    var onFinish: (() -> Void)?

    // MARK: - Stored

    private let letter: String
    private let configuration: Configuration

    /// Used by `.fadeScale`.
    private let label = UILabel()
    /// Used by `.strokeDraw` (stroke) and `.maskReveal` (mask).
    private let shapeLayer = CAShapeLayer()
    /// The filled view revealed in `.maskReveal`.
    private let fillView = UIView()

    private var hasLaidOutGlyph = false
    private var hasPlayed = false

    // MARK: - Init

    init(letter: String, configuration: Configuration = .default) {
        self.letter = letter
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — SplashView is programmatic.")
    }

    // MARK: - Setup

    private func setUp() {
        backgroundColor = configuration.backgroundColorValue

        switch configuration.entrance {
        case .fadeScale:
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = letter
            label.font = configuration.font
            label.textColor = configuration.textColor
            label.textAlignment = .center
            // Start hidden; `play()` springs it in.
            label.alpha = 0
            label.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])

        case .strokeDraw:
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.strokeColor = configuration.textColor.cgColor
            shapeLayer.lineWidth = 4
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            shapeLayer.strokeEnd = 0
            layer.addSublayer(shapeLayer)

        case .maskReveal:
            fillView.backgroundColor = configuration.textColor
            fillView.alpha = 0
            fillView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            shapeLayer.fillColor = UIColor.black.cgColor
            fillView.layer.mask = shapeLayer
            addSubview(fillView)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        if configuration.entrance == .maskReveal {
            fillView.frame = bounds
        }

        // Build / center the glyph path once we have real bounds.
        if !hasLaidOutGlyph,
           configuration.entrance == .strokeDraw || configuration.entrance == .maskReveal {
            if let path = centeredGlyphPath() {
                shapeLayer.frame = bounds
                shapeLayer.path = path
                hasLaidOutGlyph = true
            }
        }
    }

    // MARK: - Glyph path (CoreText)

    /// Derives the configured letter's outline as a CGPath, flipped to UIKit's
    /// coordinate space and centered within `bounds`.
    private func centeredGlyphPath() -> CGPath? {
        guard let firstChar = letter.first else { return nil }

        let ctFont = CTFontCreateWithFontDescriptor(
            configuration.font.fontDescriptor as CTFontDescriptor,
            configuration.font.pointSize,
            nil
        )

        // Map the first character (handle surrogate pairs) to a glyph.
        var characters = Array(String(firstChar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let gotGlyphs = CTFontGetGlyphsForCharacters(
            ctFont, &characters, &glyphs, characters.count
        )
        guard gotGlyphs, let glyph = glyphs.first, glyph != 0 else { return nil }

        guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            return nil
        }

        // CoreText paths are y-up; flip vertically into UIKit space.
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        guard let flipped = glyphPath.copy(using: &flip) else { return nil }

        // Center the (flipped) glyph bounding box in our bounds.
        let glyphBounds = flipped.boundingBoxOfPath
        let dx = bounds.midX - glyphBounds.midX
        let dy = bounds.midY - glyphBounds.midY
        var center = CGAffineTransform(translationX: dx, y: dy)
        return flipped.copy(using: &center)
    }

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            play()
        }
    }

    // MARK: - Play

    /// Runs the entrance animation. Safe to call directly; auto-runs once the
    /// view gains a window. Guarded so it never replays.
    func play() {
        guard !hasPlayed else { return }
        // Layout must have produced a glyph path for the path-based styles.
        if configuration.entrance != .fadeScale {
            layoutIfNeeded()
            guard hasLaidOutGlyph else { return }
        }
        hasPlayed = true

        switch configuration.entrance {
        case .fadeScale:
            playFadeScale()
        case .strokeDraw:
            playStrokeDraw()
        case .maskReveal:
            playMaskReveal()
        }
    }

    private func playFadeScale() {
        let spring = Inlay.Spring(duration: configuration.duration, bounce: 0.35)
        Inlay.SpringAnimator.animate(
            spring,
            animations: { [label] in
                label.alpha = 1
                label.transform = .identity
            },
            completion: { [weak self] in
                self?.finish()
            }
        )
    }

    private func playStrokeDraw() {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.finish()
        }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = configuration.duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        shapeLayer.strokeEnd = 1
        shapeLayer.add(animation, forKey: "strokeDraw")
        CATransaction.commit()
    }

    private func playMaskReveal() {
        let spring = Inlay.Spring(duration: configuration.duration, bounce: 0.3)
        Inlay.SpringAnimator.animate(
            spring,
            animations: { [fillView] in
                fillView.alpha = 1
                fillView.transform = .identity
            },
            completion: { [weak self] in
                self?.finish()
            }
        )
    }

    private func finish() {
        onFinish?()
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // Refresh CG-backed colors for dark/light switches.
        if configuration.entrance == .strokeDraw {
            shapeLayer.strokeColor = configuration.textColor.resolvedColor(with: traitCollection).cgColor
        }
    }
}
