//
//  Inlay+SpringAnimator.swift
//  Inlay — shared primitive
//
//  Installed once. Multiple components depend on this file.
//  Do not rename `Inlay` or its members — components reference them by name.
//

import UIKit

/// Root namespace for Inlay's shared primitives and design tokens.
/// Everything shared between components nests under here so that copying
/// two components never produces a duplicate top-level type.
enum Inlay {}

extension Inlay {

    /// A simple, designer-friendly spring token.
    ///
    /// `bounce` is the only knob most people touch:
    ///   - `0.0`  → no overshoot (critically damped)
    ///   - `0.3`  → lively, natural (default)
    ///   - `0.5+` → playful, very springy
    struct Spring {
        var duration: TimeInterval
        var bounce: CGFloat

        init(duration: TimeInterval = 0.5, bounce: CGFloat = 0.3) {
            self.duration = duration
            self.bounce = bounce
        }

        /// A few ready-made springs so callers rarely need raw numbers.
        static let snappy   = Spring(duration: 0.35, bounce: 0.15)
        static let lively   = Spring(duration: 0.5,  bounce: 0.3)
        static let playful  = Spring(duration: 0.6,  bounce: 0.45)
        static let gentle   = Spring(duration: 0.55, bounce: 0.0)
    }

    /// Tiny wrapper over `UIViewPropertyAnimator` that maps a `Spring` token
    /// to a configured spring timing curve. Keeps animation code in every
    /// component down to one line.
    enum SpringAnimator {

        /// Convenience: trailing-closure call site.
        ///   `Inlay.SpringAnimator.animate(.lively) { view.transform = .identity }`
        static func animate(
            _ spring: Inlay.Spring,
            _ animations: @escaping () -> Void
        ) {
            animate(spring, animations: animations, completion: nil)
        }

        static func animate(
            _ spring: Inlay.Spring,
            animations: @escaping () -> Void,
            completion: (() -> Void)?
        ) {
            let damping = dampingRatio(forBounce: spring.bounce)
            let timing = UISpringTimingParameters(dampingRatio: damping)
            let animator = UIViewPropertyAnimator(
                duration: spring.duration,
                timingParameters: timing
            )
            animator.addAnimations(animations)
            if let completion {
                animator.addCompletion { _ in completion() }
            }
            animator.startAnimation()
        }

        /// Maps `bounce` (0...~0.9) to a damping ratio (1...0.1).
        private static func dampingRatio(forBounce bounce: CGFloat) -> CGFloat {
            let clamped = max(0, min(bounce, 0.9))
            return 1 - clamped
        }
    }
}
