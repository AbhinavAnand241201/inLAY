//
//  TypewriterLabel.swift
//  Inlay — component
//
//  A label that types itself in, character-by-character, with a blinking caret.
//  Supports a single-string mode and a looping cycle mode that types a string,
//  pauses, deletes it, and moves on to the next — the classic hero-tagline
//  effect ("Build faster." → "Ship sooner." → "Own your code.").
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `TypewriterLabel.Configuration`.
//
//      // Single string:
//      let label = TypewriterLabel()
//      view.addSubview(label)
//      label.translatesAutoresizingMaskIntoConstraints = false
//      NSLayoutConstraint.activate([
//          label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//          label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//      ])
//      label.onFinish = { print("done typing") }
//      label.type("Hello, world.")
//
//      // Cycling hero tagline:
//      var config = TypewriterLabel.Configuration.default
//      config.font = .systemFont(ofSize: 32, weight: .bold)
//      config.loops = true
//      let hero = TypewriterLabel(configuration: config)
//      hero.cycle(["Build faster.", "Ship sooner.", "Own your code."])
//
//  Dependency: none
//

import UIKit

final class TypewriterLabel: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Font for the typed text.
        var font: UIFont = .systemFont(ofSize: 24, weight: .semibold)
        /// Color of the typed text.
        var textColor: UIColor = .label
        /// Typing speed, in characters per second.
        var typingSpeed: Double = 18
        /// Deleting speed, in characters per second (cycle mode).
        var deletingSpeed: Double = 30
        /// Pause (seconds) once a string is fully typed, before deleting.
        var pauseAfterTyping: TimeInterval = 1.4
        /// Pause (seconds) once a string is fully deleted, before the next.
        var pauseAfterDeleting: TimeInterval = 0.3
        /// Whether cycling loops back to the first string after the last.
        var loops: Bool = true
        /// Whether the blinking caret is shown.
        var showsCaret: Bool = true
        /// Color of the caret. Falls back to `textColor` when nil.
        var caretColor: UIColor? = nil
        /// Width of the caret, in points.
        var caretWidth: CGFloat = 2
        /// Caret blink period, in seconds (one fade in/out cycle).
        var caretBlinkRate: TimeInterval = 0.5
        /// Start automatically the first time the view enters a window.
        var startsOnAppear: Bool = true
        /// Text alignment of the underlying label.
        var textAlignment: NSTextAlignment = .natural
        /// Number of lines (0 = unlimited).
        var numberOfLines: Int = 1

        static let `default` = Configuration()
    }

    // MARK: - Public API

    let configuration: Configuration

    /// Called when a single-string `type(_:)` finishes. Not called in cycle mode.
    var onFinish: (() -> Void)?

    /// `true` while typing or deleting is actively in progress.
    private(set) var isRunning = false

    // MARK: - Private state

    private enum Mode {
        case idle
        case single(String)
        case cycle([String])
    }

    private enum Phase {
        case typing
        case pausingAfterTyping
        case deleting
        case pausingAfterDeleting
    }

    private let label = UILabel()
    private let caret = UIView()

    private var caretWidthConstraint: NSLayoutConstraint!
    private var caretHeightConstraint: NSLayoutConstraint!

    private var mode: Mode = .idle
    private var phase: Phase = .typing
    private var cycleIndex = 0
    private var charIndex = 0
    private var current = ""
    private var hasAutoStarted = false
    private var pendingAutoStart: Mode? = nil

    private var tickTimer: Timer?
    private var pauseTimer: Timer?

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

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = configuration.font
        label.textColor = configuration.textColor
        label.textAlignment = configuration.textAlignment
        label.numberOfLines = configuration.numberOfLines
        label.text = ""
        addSubview(label)

        caret.translatesAutoresizingMaskIntoConstraints = false
        caret.backgroundColor = configuration.caretColor ?? configuration.textColor
        caret.layer.cornerRadius = configuration.caretWidth / 2
        caret.layer.cornerCurve = .continuous
        caret.isHidden = !configuration.showsCaret
        addSubview(caret)

        caretWidthConstraint = caret.widthAnchor.constraint(
            equalToConstant: configuration.caretWidth)
        caretHeightConstraint = caret.heightAnchor.constraint(
            equalToConstant: caretHeight())

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),

            // The caret hugs the trailing edge of the label's intrinsic content,
            // so it always sits right after the last typed character.
            caret.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
            caret.trailingAnchor.constraint(equalTo: trailingAnchor),
            caret.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            caretWidthConstraint,
            caretHeightConstraint,
        ])

        // Keep the label tight so the caret tracks the text edge.
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func caretHeight() -> CGFloat {
        // A caret a touch shorter than the line height reads as premium.
        max(configuration.font.lineHeight * 0.9, configuration.font.pointSize)
    }

    // MARK: - Public control

    /// Type a single string in. Calls `onFinish` when complete. Cancels any
    /// in-flight animation.
    func type(_ text: String) {
        start(mode: .single(text))
    }

    /// Cycle through several strings: type, pause, delete, repeat. Loops when
    /// `configuration.loops` is true. Cancels any in-flight animation.
    func cycle(_ texts: [String]) {
        let nonEmpty = texts.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return }
        start(mode: .cycle(nonEmpty))
    }

    /// Pause the animation in place (timers stop; state is preserved).
    func pause() {
        guard isRunning else { return }
        isRunning = false
        invalidateTimers()
    }

    /// Resume after `pause()`.
    func resume() {
        guard !isRunning, !isIdle else { return }
        isRunning = true
        scheduleNext()
    }

    /// Stop and clear all state and displayed text.
    func reset() {
        invalidateTimers()
        isRunning = false
        mode = .idle
        phase = .typing
        cycleIndex = 0
        charIndex = 0
        current = ""
        label.text = ""
        startCaretBlink()
    }

    // MARK: - Driver

    private var isIdle: Bool {
        if case .idle = mode { return true }
        return false
    }

    private func start(mode newMode: Mode) {
        // Defer until we're in a window if startsOnAppear is set and we haven't
        // appeared yet — mirrors how the FloatingToolbar defers its entrance.
        if configuration.startsOnAppear, window == nil, !hasAutoStarted {
            pendingAutoStart = newMode
            // Still prime the displayed string so layout is stable pre-appear.
            primeState(for: newMode)
            return
        }
        pendingAutoStart = nil
        primeState(for: newMode)
        isRunning = true
        startCaretBlink()
        scheduleNext()
    }

    private func primeState(for newMode: Mode) {
        invalidateTimers()
        mode = newMode
        phase = .typing
        cycleIndex = 0
        charIndex = 0
        current = displayString(for: newMode, at: 0) ?? ""
        label.text = ""
    }

    private func displayString(for mode: Mode, at index: Int) -> String? {
        switch mode {
        case .idle: return nil
        case .single(let s): return s
        case .cycle(let arr):
            guard arr.indices.contains(index) else { return nil }
            return arr[index]
        }
    }

    private func scheduleNext() {
        guard isRunning else { return }
        switch phase {
        case .typing:
            scheduleTick(interval: 1.0 / max(configuration.typingSpeed, 0.01),
                         action: { [weak self] in self?.typeStep() })
        case .deleting:
            scheduleTick(interval: 1.0 / max(configuration.deletingSpeed, 0.01),
                         action: { [weak self] in self?.deleteStep() })
        case .pausingAfterTyping:
            schedulePause(after: configuration.pauseAfterTyping) { [weak self] in
                self?.phase = .deleting
                self?.scheduleNext()
            }
        case .pausingAfterDeleting:
            schedulePause(after: configuration.pauseAfterDeleting) { [weak self] in
                self?.advanceToNextString()
            }
        }
    }

    private func typeStep() {
        let chars = Array(current)
        guard charIndex < chars.count else {
            finishedTyping()
            return
        }
        charIndex += 1
        label.text = String(chars[0..<charIndex])
        if charIndex >= chars.count {
            finishedTyping()
        } else {
            scheduleNext()
        }
    }

    private func deleteStep() {
        guard charIndex > 0 else {
            finishedDeleting()
            return
        }
        charIndex -= 1
        let chars = Array(current)
        label.text = String(chars[0..<charIndex])
        if charIndex == 0 {
            finishedDeleting()
        } else {
            scheduleNext()
        }
    }

    private func finishedTyping() {
        switch mode {
        case .single:
            isRunning = false
            invalidateTimers()
            onFinish?()
        case .cycle:
            phase = .pausingAfterTyping
            scheduleNext()
        case .idle:
            isRunning = false
        }
    }

    private func finishedDeleting() {
        phase = .pausingAfterDeleting
        scheduleNext()
    }

    private func advanceToNextString() {
        guard case .cycle(let arr) = mode else { return }
        var next = cycleIndex + 1
        if next >= arr.count {
            if configuration.loops {
                next = 0
            } else {
                isRunning = false
                invalidateTimers()
                return
            }
        }
        cycleIndex = next
        current = arr[next]
        charIndex = 0
        phase = .typing
        label.text = ""
        scheduleNext()
    }

    // MARK: - Timers

    private func scheduleTick(interval: TimeInterval, action: @escaping () -> Void) {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func schedulePause(after delay: TimeInterval,
                               action: @escaping () -> Void) {
        pauseTimer?.invalidate()
        let timer = Timer(timeInterval: max(delay, 0), repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func invalidateTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    // MARK: - Caret blink

    private func startCaretBlink() {
        guard configuration.showsCaret else {
            caret.isHidden = true
            return
        }
        caret.isHidden = false
        caret.layer.removeAllAnimations()
        caret.alpha = 1
        UIView.animate(
            withDuration: max(configuration.caretBlinkRate, 0.05),
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction],
            animations: { [weak self] in self?.caret.alpha = 0 },
            completion: nil)
    }

    private func stopCaretBlink() {
        caret.layer.removeAllAnimations()
        caret.alpha = 1
    }

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startCaretBlink()
            if configuration.startsOnAppear, !hasAutoStarted,
               let pending = pendingAutoStart {
                hasAutoStarted = true
                start(mode: pending)
            } else if isRunning {
                // Returning to a window — keep going.
                scheduleNext()
            }
        } else {
            // Removed from window: cancel all timers, stop the blink.
            invalidateTimers()
            stopCaretBlink()
        }
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        let caretSpace = configuration.showsCaret ? configuration.caretWidth + 2 : 0
        return CGSize(width: labelSize.width + caretSpace, height: caretHeight())
    }
}
