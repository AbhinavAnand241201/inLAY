//
//  RevealView.swift
//  Inlay — component
//
//  A shape (rounded rectangle or circle) that springs open from the center,
//  scaling from 0% to 100%. Use it for reveal animations, success badges,
//  expanding panels, attention pulses, etc. Handles both the "box grows from
//  center" and "circle grows from center" cases via `Configuration.shape`.
//
//      let box = RevealView()                 // reveals automatically on appear
//      let circle = RevealView(configuration: {
//          var c = RevealView.Configuration.default
//          c.shape = .circle
//          c.fillColor = .systemGreen
//          return c
//      }())
//      // trigger manually:  box.reveal()  /  box.conceal()  /  box.toggle()
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class RevealView: UIView {

    // MARK: - Configuration

    struct Configuration {
        var shape: Shape = .roundedRect(cornerRadius: 20)
        var fillColor: UIColor = .tintColor
        var animation: Inlay.Spring = .playful
        /// Near-zero so the start matrix stays invertible (avoids transform warnings).
        var collapsedScale: CGFloat = 0.01
        /// Reveal automatically the first time the view appears.
        var revealsOnAppear: Bool = true

        enum Shape {
            case roundedRect(cornerRadius: CGFloat)
            case circle
        }
        static let `default` = Configuration()
    }

    // MARK: - Private

    private let configuration: Configuration
    private let shapeView = UIView()
    private var isRevealed = false
    private var hasAutoRevealed = false

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

    // MARK: - Public

    /// Optional content centered inside the shape (a checkmark, label, icon…).
    func setContent(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        shapeView.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: shapeView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: shapeView.centerYAnchor),
        ])
    }

    func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.shapeView.transform = .identity
        }
    }

    func conceal() {
        guard isRevealed else { return }
        isRevealed = false
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.shapeView.transform = self.collapsedTransform
        }
    }

    func toggle() { isRevealed ? conceal() : reveal() }

    // MARK: - Setup

    private var collapsedTransform: CGAffineTransform {
        CGAffineTransform(scaleX: configuration.collapsedScale, y: configuration.collapsedScale)
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        shapeView.backgroundColor = configuration.fillColor
        shapeView.layer.cornerCurve = .continuous
        shapeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shapeView)
        NSLayoutConstraint.activate([
            shapeView.topAnchor.constraint(equalTo: topAnchor),
            shapeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            shapeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            shapeView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Transforms scale from the view's center by default — exactly what we want.
        shapeView.transform = collapsedTransform
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch configuration.shape {
        case .roundedRect(let radius):
            shapeView.layer.cornerRadius = radius
        case .circle:
            shapeView.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, configuration.revealsOnAppear, !hasAutoRevealed else { return }
        hasAutoRevealed = true
        DispatchQueue.main.async { [weak self] in self?.reveal() }
    }
}
