//
//  BouncingLoader.swift
//  Inlay — component
//
//  A playful loading / buffering indicator: a row of small dots with a slightly
//  larger ball bouncing above them. Starts automatically when shown and pauses
//  when removed from the screen.
//
//      let loader = BouncingLoader()
//      view.addSubview(loader)
//      loader.centerInSuperview()      // or your own constraints
//      // loader.startAnimating() / loader.stopAnimating() to control manually
//
//  No registry dependencies — pure UIKit.
//

import UIKit

final class BouncingLoader: UIView {

    // MARK: - Configuration

    struct Configuration {
        var dotCount: Int = 3
        var dotSize: CGFloat = 8
        var dotSpacing: CGFloat = 10
        var dotColor: UIColor = .quaternaryLabel
        var ballSize: CGFloat = 12
        var ballColor: UIColor = .tintColor
        var bounceHeight: CGFloat = 18
        var bounceDuration: TimeInterval = 0.45
        var autoStarts: Bool = true
        static let `default` = Configuration()
    }

    // MARK: - Private

    private let configuration: Configuration
    private let dotsStack = UIStackView()
    private let ball = UIView()
    private var isAnimating = false

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

        dotsStack.axis = .horizontal
        dotsStack.alignment = .center
        dotsStack.spacing = configuration.dotSpacing
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotsStack)

        for _ in 0 ..< max(1, configuration.dotCount) {
            let dot = UIView()
            dot.backgroundColor = configuration.dotColor
            dot.layer.cornerRadius = configuration.dotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: configuration.dotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: configuration.dotSize).isActive = true
            dotsStack.addArrangedSubview(dot)
        }

        ball.backgroundColor = configuration.ballColor
        ball.layer.cornerRadius = configuration.ballSize / 2
        ball.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ball)

        NSLayoutConstraint.activate([
            dotsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotsStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            ball.widthAnchor.constraint(equalToConstant: configuration.ballSize),
            ball.heightAnchor.constraint(equalToConstant: configuration.ballSize),
            ball.centerXAnchor.constraint(equalTo: centerXAnchor),
            ball.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -4),

            heightAnchor.constraint(
                greaterThanOrEqualToConstant:
                    configuration.ballSize + configuration.bounceHeight + configuration.dotSize + 8
            ),
        ])
    }

    // MARK: - Control

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        ball.transform = .identity
        UIView.animate(
            withDuration: configuration.bounceDuration,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseOut],
            animations: {
                self.ball.transform = CGAffineTransform(
                    translationX: 0, y: -self.configuration.bounceHeight
                )
            }
        )
    }

    func stopAnimating() {
        isAnimating = false
        ball.layer.removeAllAnimations()
        ball.transform = .identity
    }

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if configuration.autoStarts { startAnimating() }
        } else {
            // Pause off-screen so we don't burn cycles; allow restart later.
            isAnimating = false
            ball.layer.removeAllAnimations()
        }
    }
}
