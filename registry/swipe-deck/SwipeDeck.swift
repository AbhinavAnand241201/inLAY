//
//  SwipeDeck.swift
//  Inlay — component
//
//  A Tinder-style card deck. Drag the top card and it follows your finger,
//  rotating about a lowered pivot for a natural pendulum feel. Cards behind
//  peek through, scaled down and offset, then animate forward as the top card
//  leaves. Fling past the threshold (or with enough velocity) and the card
//  flies off-screen in that direction; release short of it and the card springs
//  back. Optional like / nope / up overlays fade in proportionally to the drag.
//
//  Generic over your card model — `cardProvider` builds the view for each card.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SwipeDeck.Configuration`.
//
//      struct Profile { let name: String; let color: UIColor }
//
//      let deck = SwipeDeck(cards: profiles) { profile in
//          let card = UIView()
//          card.backgroundColor = profile.color
//          let label = UILabel()
//          label.text = profile.name
//          label.translatesAutoresizingMaskIntoConstraints = false
//          card.addSubview(label)
//          NSLayoutConstraint.activate([
//              label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
//              label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
//          ])
//          return card
//      }
//      deck.onSwipe = { profile, direction in print("\(profile.name) → \(direction)") }
//      deck.onEmpty = { print("out of cards") }
//      view.addSubview(deck)            // pin with Auto Layout, give it a size
//
//      // Drive it from buttons, too:
//      deck.swipe(.right)
//      deck.undo()                      // requires `configuration.allowsUndo`
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SwipeDeck<Card>: UIView {

    // MARK: - Direction

    /// The way a card left the deck.
    enum Direction {
        case left, right, up

        /// Unit vector pointing toward the off-screen target.
        fileprivate var vector: CGVector {
            switch self {
            case .left:  return CGVector(dx: -1, dy: 0)
            case .right: return CGVector(dx:  1, dy: 0)
            case .up:    return CGVector(dx:  0, dy: -1)
            }
        }
    }

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// How many cards are rendered in the peeked stack at once.
        var visibleCards: Int = 3
        /// Each card behind the top shrinks by this fraction (0.06 → 6%).
        var stackScaleStep: CGFloat = 0.06
        /// Each card behind the top is pushed down by this many points.
        var stackYOffset: CGFloat = 14
        /// Maximum tilt of the top card, in degrees, at full drag.
        var maxRotation: CGFloat = 12
        /// Pivot lowered below the card by this fraction of card height, so the
        /// card swings like a pendulum instead of spinning about its center.
        var rotationAnchorDrop: CGFloat = 0.6
        /// Drag distance to commit a swipe, as a fraction of the deck width.
        var swipeThreshold: CGFloat = 0.32
        /// A flick faster than this (points/sec) commits regardless of distance.
        var velocityThreshold: CGFloat = 900
        /// Allow flinging a card straight up (e.g. a "super like").
        var allowsUpSwipe: Bool = false
        /// Below the threshold the card springs back instead of leaving.
        var springsBackBelowThreshold: Bool = true
        /// Enable `undo()` to bring back the most recently swiped card.
        var allowsUndo: Bool = true
        /// Insets of each card within the deck's bounds.
        var cardInsets: UIEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
        /// Corner radius of each hosted card container.
        var cornerRadius: CGFloat = 20
        /// Spring used for restack, spring-back, and programmatic swipes.
        var animation: Inlay.Spring = .lively
        /// Haptic feedback when a card flings off.
        var hapticsEnabled: Bool = true

        // A generic class can't hold a static *stored* property, so expose
        // `.default` as a computed property.
        static var `default`: Configuration { Configuration() }
    }

    // MARK: - Public API

    /// Called the moment a card commits to leaving, with the direction it left.
    var onSwipe: ((Card, Direction) -> Void)?
    /// Called once when the last card has left the deck.
    var onEmpty: (() -> Void)?
    /// Whether `undo()` can currently restore a card.
    var allowsUndo: Bool { configuration.allowsUndo && !history.isEmpty }

    // MARK: - Overlays

    /// Builder for an overlay view shown over the top card while dragging in a
    /// given direction. Return your own badge/gradient; opacity is driven for
    /// you. Set via `setOverlay(for:_:)`.
    private var overlayBuilders: [Direction: () -> UIView] = [:]

    /// Provide an overlay view for a swipe direction (e.g. a "LIKE" stamp).
    /// Its `alpha` is animated from 0…1 as the drag approaches the threshold.
    func setOverlay(for direction: Direction, _ builder: @escaping () -> UIView) {
        overlayBuilders[direction] = builder
        rebuildVisibleStack()
    }

    // MARK: - Card host

    /// Container that hosts one user-provided card view and its overlays.
    private final class CardHost: UIView {
        let content: UIView
        var card: Card
        var overlays: [Direction: UIView] = [:]

        init(card: Card, content: UIView, cornerRadius: CGFloat) {
            self.card = card
            self.content = content
            super.init(frame: .zero)
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
            // Shadow on the host; corners clip on an inner wrapper so the
            // shadow is never clipped away.
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.22
            layer.shadowRadius = 16
            layer.shadowOffset = CGSize(width: 0, height: 10)

            let clip = UIView()
            clip.layer.cornerRadius = cornerRadius
            clip.layer.cornerCurve = .continuous
            clip.clipsToBounds = true
            clip.translatesAutoresizingMaskIntoConstraints = false
            addSubview(clip)

            content.translatesAutoresizingMaskIntoConstraints = false
            clip.addSubview(content)
            NSLayoutConstraint.activate([
                clip.topAnchor.constraint(equalTo: topAnchor),
                clip.bottomAnchor.constraint(equalTo: bottomAnchor),
                clip.leadingAnchor.constraint(equalTo: leadingAnchor),
                clip.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: clip.topAnchor),
                content.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.shadowPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: layer.cornerRadius
            ).cgPath
        }
    }

    // MARK: - State

    private let configuration: Configuration
    private let cardProvider: (Card) -> UIView

    /// Remaining cards, top of the deck at index 0.
    private var cards: [Card]
    /// Live hosts for the visible window, hosts.first == top card.
    private var hosts: [CardHost] = []
    /// Swiped-away cards for `undo()`, most recent last.
    private var history: [(card: Card, direction: Direction)] = []

    private var didNotifyEmpty = false

    // Drag bookkeeping.
    private var panStart: CGPoint = .zero
    private var topStartCenter: CGPoint = .zero

    // MARK: - Init

    init(
        cards: [Card],
        configuration: Configuration = .default,
        cardProvider: @escaping (Card) -> UIView
    ) {
        self.configuration = configuration
        self.cardProvider = cardProvider
        self.cards = cards
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    // MARK: - Cards source

    /// Replace the whole deck and restack from scratch.
    func setCards(_ cards: [Card]) {
        for host in hosts { host.removeFromSuperview() }
        hosts.removeAll()
        history.removeAll()
        self.cards = cards
        didNotifyEmpty = false
        rebuildVisibleStack()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if hosts.isEmpty && !cards.isEmpty {
            rebuildVisibleStack()
        } else {
            layoutStack(animated: false)
        }
    }

    /// Frame for a card at a given depth (0 == top) in the stack.
    private func cardFrame(forDepth depth: Int) -> CGRect {
        let inset = configuration.cardInsets
        let base = bounds.inset(by: inset)
        return base
    }

    /// Transform for a card at a given depth in the resting stack.
    private func restingTransform(forDepth depth: Int) -> CGAffineTransform {
        let d = CGFloat(depth)
        let scale = 1 - configuration.stackScaleStep * d
        let y = configuration.stackYOffset * d
        return CGAffineTransform(translationX: 0, y: y).scaledBy(x: scale, y: scale)
    }

    /// Build (or rebuild) the window of visible hosts from the front of `cards`.
    private func rebuildVisibleStack() {
        guard bounds.width > 0, bounds.height > 0 else {
            setNeedsLayout()
            return
        }
        // Tear down existing hosts.
        for host in hosts { host.removeFromSuperview() }
        hosts.removeAll()

        let count = min(configuration.visibleCards, cards.count)
        guard count > 0 else {
            notifyEmptyIfNeeded()
            return
        }

        // Build back-to-front so the top card ends up on top of the z-order.
        for depth in stride(from: count - 1, through: 0, by: -1) {
            let card = cards[depth]
            let host = makeHost(for: card)
            host.frame = cardFrame(forDepth: depth)
            host.transform = restingTransform(forDepth: depth)
            addSubview(host)
            // hosts[0] should be the top card.
            hosts.insert(host, at: 0)
            host.layoutIfNeeded()
        }
        updateOverlayAlphas(translation: .zero)
    }

    private func makeHost(for card: Card) -> CardHost {
        let content = cardProvider(card)
        let host = CardHost(
            card: card,
            content: content,
            cornerRadius: configuration.cornerRadius
        )
        // Attach configured overlays, hidden initially.
        for (direction, builder) in overlayBuilders {
            let overlay = builder()
            overlay.alpha = 0
            overlay.isUserInteractionEnabled = false
            overlay.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: host.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
            host.overlays[direction] = overlay
        }
        return host
    }

    /// Re-frame & re-transform every host to its resting position.
    private func layoutStack(animated: Bool) {
        let apply = {
            for (depth, host) in self.hosts.enumerated() {
                host.frame = self.cardFrame(forDepth: depth)
                host.transform = self.restingTransform(forDepth: depth)
            }
        }
        if animated {
            Inlay.SpringAnimator.animate(configuration.animation, apply)
        } else {
            apply()
        }
    }

    // MARK: - Pan

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let top = hosts.first else { return }
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            topStartCenter = top.center

        case .changed:
            applyDrag(to: top, translation: translation)
            updateOverlayAlphas(translation: translation)

        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: self)
            finishDrag(top: top, translation: translation, velocity: velocity)

        default:
            break
        }
    }

    /// Position + rotate the top card to follow a drag translation.
    private func applyDrag(to top: CardHost, translation: CGPoint) {
        top.center = CGPoint(
            x: topStartCenter.x + translation.x,
            y: topStartCenter.y + translation.y
        )
        let fraction = translation.x / max(bounds.width, 1)
        let radians = rotation(forFraction: fraction)
        top.transform = CGAffineTransform(rotationAngle: radians)
        // Reveal the next card progressively as the top one is dragged.
        let progress = min(abs(fraction) / configuration.swipeThreshold, 1)
        advanceBackingCards(progress: progress)
    }

    /// Rotation about a lowered pivot, expressed as a plain rotation because
    /// the host is centered; the lowered-anchor feel comes from coupling angle
    /// to horizontal translation only.
    private func rotation(forFraction fraction: CGFloat) -> CGFloat {
        let maxRadians = configuration.maxRotation * .pi / 180
        let clamped = max(-1, min(fraction / configuration.swipeThreshold, 1))
        // Sign by drag direction; lowered anchor → rotate the same way you push.
        let anchorSign: CGFloat = configuration.rotationAnchorDrop >= 0 ? 1 : -1
        return clamped * maxRadians * anchorSign
    }

    /// Animate the cards behind the top toward their next resting depth.
    private func advanceBackingCards(progress: CGFloat) {
        for (depth, host) in hosts.enumerated() where depth > 0 {
            let from = restingTransform(forDepth: depth)
            let to = restingTransform(forDepth: depth - 1)
            host.transform = interpolate(from: from, to: to, t: progress)
        }
    }

    private func interpolate(
        from: CGAffineTransform,
        to: CGAffineTransform,
        t: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: from.a + (to.a - from.a) * t,
            b: from.b + (to.b - from.b) * t,
            c: from.c + (to.c - from.c) * t,
            d: from.d + (to.d - from.d) * t,
            tx: from.tx + (to.tx - from.tx) * t,
            ty: from.ty + (to.ty - from.ty) * t
        )
    }

    // MARK: - Commit / spring back

    private func finishDrag(top: CardHost, translation: CGPoint, velocity: CGPoint) {
        let widthThreshold = bounds.width * configuration.swipeThreshold
        let horizontalCommit =
            abs(translation.x) > widthThreshold ||
            abs(velocity.x) > configuration.velocityThreshold
        let verticalCommit =
            configuration.allowsUpSwipe &&
            (-translation.y > bounds.height * configuration.swipeThreshold ||
             -velocity.y > configuration.velocityThreshold) &&
            abs(translation.y) > abs(translation.x)

        if verticalCommit {
            commitSwipe(top: top, direction: .up, velocity: velocity)
        } else if horizontalCommit {
            commitSwipe(top: top, direction: translation.x > 0 ? .right : .left, velocity: velocity)
        } else if configuration.springsBackBelowThreshold {
            springBack(top: top)
        } else {
            // Honor the drag even below threshold: leave the way it was headed.
            let dir: Direction
            if configuration.allowsUpSwipe && abs(translation.y) > abs(translation.x) && translation.y < 0 {
                dir = .up
            } else {
                dir = translation.x >= 0 ? .right : .left
            }
            commitSwipe(top: top, direction: dir, velocity: velocity)
        }
    }

    private func springBack(top: CardHost) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            top.center = self.topStartCenter
            top.transform = .identity
            self.advanceBackingCards(progress: 0)
            self.updateOverlayAlphas(translation: .zero)
        }
    }

    /// Fling the top card off-screen and promote the deck.
    private func commitSwipe(top: CardHost, direction: Direction, velocity: CGPoint) {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // Lock in the overlay for the committed direction.
        for (dir, overlay) in top.overlays { overlay.alpha = (dir == direction) ? 1 : 0 }

        let card = cards.isEmpty ? nil : cards.removeFirst()
        hosts.removeFirst()
        if let card { history.append((card, direction)) }

        // Target far off-screen along the swipe vector, keeping current angle.
        let vector = direction.vector
        let distance = max(bounds.width, bounds.height) * 1.6
        let currentAngle = atan2(top.transform.b, top.transform.a)
        let targetCenter = CGPoint(
            x: top.center.x + vector.dx * distance + (direction == .up ? velocity.x * 0.05 : 0),
            y: top.center.y + vector.dy * distance + (direction != .up ? velocity.y * 0.05 : 0)
        )
        let flingAngle = currentAngle + (direction == .up ? 0 : vector.dx * (configuration.maxRotation * .pi / 180))

        // Promote the remaining hosts forward.
        layoutStack(animated: true)
        // Pull the next card into the window, if any.
        appendNextHostIfAvailable()

        Inlay.SpringAnimator.animate(.gentle, animations: {
            top.center = targetCenter
            top.transform = CGAffineTransform(rotationAngle: flingAngle)
            top.alpha = 0
        }, completion: {
            top.removeFromSuperview()
        })

        if let card { onSwipe?(card, direction) }
        if cards.isEmpty { notifyEmptyIfNeeded() }
    }

    /// Add a freshly revealed card at the back of the visible window.
    private func appendNextHostIfAvailable() {
        let nextIndex = hosts.count // depth of the slot we want to fill
        guard nextIndex < configuration.visibleCards, nextIndex < cards.count else { return }
        let card = cards[nextIndex]
        let host = makeHost(for: card)
        host.frame = cardFrame(forDepth: nextIndex)
        // Start one step further back, then settle in via layoutStack spring.
        host.transform = restingTransform(forDepth: nextIndex + 1)
        host.alpha = 0
        insertSubview(host, at: 0) // behind existing cards
        hosts.append(host)
        host.layoutIfNeeded()
        Inlay.SpringAnimator.animate(configuration.animation) {
            host.transform = self.restingTransform(forDepth: nextIndex)
            host.alpha = 1
        }
    }

    // MARK: - Overlays

    private func updateOverlayAlphas(translation: CGPoint) {
        guard let top = hosts.first else { return }
        let widthThreshold = max(bounds.width * configuration.swipeThreshold, 1)
        let heightThreshold = max(bounds.height * configuration.swipeThreshold, 1)

        let horizontal = translation.x / widthThreshold
        let vertical = -translation.y / heightThreshold

        for (direction, overlay) in top.overlays {
            let mag: CGFloat
            switch direction {
            case .right: mag = max(0, horizontal)
            case .left:  mag = max(0, -horizontal)
            case .up:    mag = configuration.allowsUpSwipe ? max(0, vertical) : 0
            }
            overlay.alpha = min(mag, 1)
        }
    }

    // MARK: - Programmatic

    /// Fling the current top card in a direction, as if the user swiped it.
    func swipe(_ direction: Direction) {
        guard let top = hosts.first else { return }
        if direction == .up && !configuration.allowsUpSwipe { return }
        topStartCenter = top.center
        commitSwipe(top: top, direction: direction, velocity: .zero)
    }

    /// Bring back the most recently swiped card, if `allowsUndo`.
    func undo() {
        guard configuration.allowsUndo, let last = history.popLast() else { return }
        cards.insert(last.card, at: 0)
        didNotifyEmpty = false

        // Trim the window if it's already full, then build the returning host.
        if hosts.count >= configuration.visibleCards, let back = hosts.popLast() {
            back.removeFromSuperview()
        }
        // Push existing hosts back one depth.
        layoutStack(animated: true) // they'll be re-depthed after insert below

        let host = makeHost(for: last.card)
        host.frame = cardFrame(forDepth: 0)
        addSubview(host) // top of z-order
        hosts.insert(host, at: 0)
        host.layoutIfNeeded()

        // Fly the card back in from the direction it left.
        let vector = last.direction.vector
        let distance = max(bounds.width, bounds.height) * 1.4
        host.center = CGPoint(
            x: host.center.x + vector.dx * distance,
            y: host.center.y + vector.dy * distance
        )
        let angle = (last.direction == .up ? 0 : vector.dx * (configuration.maxRotation * .pi / 180))
        host.transform = CGAffineTransform(rotationAngle: angle)
        host.alpha = 1

        // Re-depth everything to its correct resting position.
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.layoutStack(animated: false)
            self.updateOverlayAlphas(translation: .zero)
        }
    }

    // MARK: - Empty

    private func notifyEmptyIfNeeded() {
        guard cards.isEmpty, !didNotifyEmpty else { return }
        didNotifyEmpty = true
        onEmpty?()
    }
}
