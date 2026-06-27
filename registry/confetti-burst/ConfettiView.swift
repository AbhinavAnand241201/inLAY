//
//  ConfettiView.swift
//  Inlay — component
//
//  A celebratory confetti overlay driven by CAEmitterLayer. It mixes shapes
//  (rectangle, circle, triangle, or your own image) across a vibrant color
//  palette, tumbling and spinning for a premium, hand-tuned feel. The view is
//  user-interaction-transparent — taps pass straight through to whatever is
//  underneath, so you can drop it on top of any screen.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `ConfettiView.Configuration`.
//
//      // One-shot celebration that cleans itself up:
//      let confetti = ConfettiView()            // default: .rain
//      confetti.frame = view.bounds
//      confetti.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//      view.addSubview(confetti)
//      confetti.burst()                         // blast, then auto-remove
//
//      // Or a radial burst from a point (e.g. a tapped button center):
//      var config = ConfettiView.Configuration.default
//      config.direction = .burst
//      let pop = ConfettiView(configuration: config)
//      pop.frame = view.bounds
//      view.addSubview(pop)
//      pop.burst(at: button.center)
//
//      // Or a continuous stream you control:
//      let stream = ConfettiView()
//      stream.frame = view.bounds
//      view.addSubview(stream)
//      stream.start()
//      // … later …
//      stream.stop()
//
//  Dependency: none
//

import UIKit

final class ConfettiView: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {

        /// The geometry of an individual confetto. `.image` lets you supply
        /// custom artwork (a logo, an emoji rendered to an image, …).
        enum Shape {
            case rectangle
            case circle
            case triangle
            case image(UIImage)
        }

        /// How the confetti moves through the scene.
        enum Direction {
            /// Falls gently from the top edge across the full width.
            case rain
            /// Shoots upward from the bottom, then arcs back down under gravity.
            case fountain
            /// Explodes radially outward from a single point.
            case burst
        }

        /// The palette cells are tinted with. Cycled across all shapes.
        var colors: [UIColor]
        /// The confetto shapes mixed into the burst.
        var shapes: [Shape]
        /// Emission style. See `Direction`.
        var direction: Direction
        /// Multiplies the base birth rate. 1.0 is a lively default; push to
        /// 2–3 for a dense storm, drop to 0.3 for a subtle sprinkle.
        var intensity: CGFloat
        /// Edge length (points) of a generated confetto before scale jitter.
        var particleSize: CGFloat
        /// Base launch speed in points/second.
        var velocity: CGFloat
        /// Random scatter applied to `velocity` (points/second).
        var velocityRange: CGFloat
        /// Emission cone half-angle in radians (how wide the spray fans out).
        var spread: CGFloat
        /// How long (seconds) each confetto lives before fading.
        var lifetime: CGFloat
        /// When true, confetti rotate and tumble in 3D for realism.
        var spin: Bool
        /// Downward acceleration (points/second²). Higher = heavier fall.
        var gravity: CGFloat
        /// Per-particle scale jitter (0 = uniform, 0.5 = ±50%).
        var scaleRange: CGFloat
        /// Birth-rate fade applied to bursts so the blast tapers naturally.
        var burstDuration: CGFloat

        /// A vibrant, celebratory default: confetti rain in mixed shapes.
        static let `default` = Configuration(
            colors: [
                UIColor(red: 0.98, green: 0.24, blue: 0.40, alpha: 1.0), // raspberry
                UIColor(red: 1.00, green: 0.70, blue: 0.18, alpha: 1.0), // amber
                UIColor(red: 0.99, green: 0.92, blue: 0.30, alpha: 1.0), // lemon
                UIColor(red: 0.30, green: 0.82, blue: 0.50, alpha: 1.0), // mint
                UIColor(red: 0.25, green: 0.62, blue: 0.98, alpha: 1.0), // azure
                UIColor(red: 0.62, green: 0.40, blue: 0.98, alpha: 1.0), // violet
                UIColor(red: 1.00, green: 0.45, blue: 0.78, alpha: 1.0)  // bubblegum
            ],
            shapes: [.rectangle, .circle, .triangle],
            direction: .rain,
            intensity: 1.0,
            particleSize: 11.0,
            velocity: 220.0,
            velocityRange: 90.0,
            spread: .pi / 5,
            lifetime: 4.0,
            spin: true,
            gravity: 320.0,
            scaleRange: 0.4,
            burstDuration: 0.25
        )
    }

    // MARK: - Stored properties

    private(set) var configuration: Configuration

    /// Set when `burst(at:)` adds the view to a window for a one-shot blast and
    /// should remove itself once the party is over.
    private var removesSelfAfterBurst = false

    private var emitter: CAEmitterLayer {
        // The view is backed directly by a CAEmitterLayer.
        layer as! CAEmitterLayer
    }

    override class var layerClass: AnyClass { CAEmitterLayer.self }

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        commonInit()
    }

    override init(frame: CGRect) {
        self.configuration = .default
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Pass every touch through to the content below.
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.birthRate = 0            // dormant until start()/burst()
        emitter.emitterCells = makeCells()
    }

    // MARK: - Public control

    /// Begin a continuous, never-ending confetti stream. Call `stop()` to end.
    func start() {
        configureEmitterGeometry(burstPoint: nil)
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1
    }

    /// Stop emitting new confetti. Particles already in flight finish their
    /// lifetimes and fade out naturally.
    func stop() {
        emitter.birthRate = 0
    }

    /// Fire a one-shot celebratory blast. For `.burst` direction the explosion
    /// originates at `point` (defaults to the view's center); for `.rain` and
    /// `.fountain` the geometry spans the relevant edge and `point` is ignored.
    ///
    /// The emitter ramps its birth rate down so the blast tapers, then stops.
    /// If the view was added solely for this burst it removes itself afterward.
    func burst(at point: CGPoint? = nil) {
        configureEmitterGeometry(burstPoint: point)
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1

        let burstSeconds = max(0.05, configuration.burstDuration)
        // Cut emission after the short blast window…
        DispatchQueue.main.asyncAfter(deadline: .now() + burstSeconds) { [weak self] in
            self?.emitter.birthRate = 0
        }
        // …then, once the last particle has lived out its lifetime, tidy up.
        let totalLife = Double(burstSeconds + configuration.lifetime + 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalLife) { [weak self] in
            guard let self else { return }
            if self.removesSelfAfterBurst {
                self.removeFromSuperview()
            }
        }
    }

    // MARK: - Geometry

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the emitter geometry in sync with size changes while idle.
        if emitter.birthRate == 0 {
            configureEmitterGeometry(burstPoint: nil)
        }
    }

    private func configureEmitterGeometry(burstPoint: CGPoint?) {
        let size = bounds.size
        let scaledBirth = Float(max(0, configuration.intensity)) * 14

        switch configuration.direction {
        case .rain:
            // A wide line just above the top edge raining straight down.
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: -12)
            emitter.emitterSize = CGSize(width: size.width * 1.1, height: 1)
            setCellMotion(angle: .pi / 2, range: configuration.spread, baseVelocity: configuration.velocity * 0.5)

        case .fountain:
            // A point at the bottom center spraying upward in a cone.
            emitter.emitterShape = .point
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 8)
            emitter.emitterSize = CGSize(width: 1, height: 1)
            setCellMotion(angle: -.pi / 2, range: configuration.spread, baseVelocity: configuration.velocity)

        case .burst:
            // A point exploding outward in every direction.
            let origin = burstPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
            emitter.emitterShape = .point
            emitter.emitterPosition = origin
            emitter.emitterSize = CGSize(width: 1, height: 1)
            setCellMotion(angle: 0, range: .pi, baseVelocity: configuration.velocity)
        }

        // Birth rate is split across all cells.
        let perCell = scaledBirth / Float(max(1, emitter.emitterCells?.count ?? 1))
        emitter.emitterCells?.forEach { $0.birthRate = perCell }
    }

    private func setCellMotion(angle: CGFloat, range: CGFloat, baseVelocity: CGFloat) {
        emitter.emitterCells?.forEach { cell in
            cell.emissionLongitude = angle
            cell.emissionRange = range
            cell.velocity = baseVelocity
            cell.velocityRange = configuration.velocityRange
            cell.yAcceleration = configuration.gravity
        }
    }

    // MARK: - Cell construction

    /// Build one emitter cell per (shape × color) pairing so every blast mixes
    /// the full palette across the full set of shapes.
    private func makeCells() -> [CAEmitterCell] {
        var cells: [CAEmitterCell] = []
        let shapes = configuration.shapes.isEmpty ? [Configuration.Shape.rectangle] : configuration.shapes
        let colors = configuration.colors.isEmpty ? [UIColor.systemPink] : configuration.colors

        for shape in shapes {
            guard let image = image(for: shape) else { continue }
            for color in colors {
                cells.append(makeCell(image: image, color: color, isImageShape: isCustomImage(shape)))
            }
        }
        return cells
    }

    private func isCustomImage(_ shape: Configuration.Shape) -> Bool {
        if case .image = shape { return true }
        return false
    }

    private func makeCell(image: CGImage, color: UIColor, isImageShape: Bool) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        // Generated shapes are white masks tinted via `color`. For caller
        // images we keep original colors but still allow a subtle tint blend.
        cell.color = (isImageShape ? color.withAlphaComponent(0.0) : color).cgColor
        if isImageShape { cell.color = UIColor.white.cgColor }

        cell.lifetime = Float(configuration.lifetime)
        cell.lifetimeRange = Float(configuration.lifetime) * 0.35
        cell.scale = 1.0
        cell.scaleRange = configuration.scaleRange
        cell.alphaSpeed = -1.0 / Float(max(0.5, configuration.lifetime)) // fade as it dies
        cell.alphaRange = 0.15

        if configuration.spin {
            // Spin around the screen-normal, plus tumble in X/Y for 3D realism.
            cell.spin = 3.5
            cell.spinRange = 6.0
        } else {
            cell.spin = 0
            cell.spinRange = 0.6
        }
        return cell
    }

    // MARK: - Shape image generation

    /// Cache so repeated bursts don't re-render the same primitive.
    private var imageCache: [String: CGImage] = [:]

    private func image(for shape: Configuration.Shape) -> CGImage? {
        switch shape {
        case .image(let custom):
            return custom.cgImage
        case .rectangle:
            return cachedShapeImage(key: "rect") { renderRectangle() }
        case .circle:
            return cachedShapeImage(key: "circle") { renderCircle() }
        case .triangle:
            return cachedShapeImage(key: "triangle") { renderTriangle() }
        }
    }

    private func cachedShapeImage(key: String, _ make: () -> CGImage?) -> CGImage? {
        let cacheKey = "\(key)-\(Int(configuration.particleSize))"
        if let hit = imageCache[cacheKey] { return hit }
        let made = make()
        if let made { imageCache[cacheKey] = made }
        return made
    }

    /// Confetti are drawn white so `CAEmitterCell.color` can tint them.
    private func renderRectangle() -> CGImage? {
        // Confetti strips read best slightly taller than wide.
        let w = configuration.particleSize
        let h = configuration.particleSize * 1.5
        let renderer = imageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            UIBezierPath(roundedRect: rect, cornerRadius: w * 0.18).fill()
            ctx.cgContext.setBlendMode(.normal)
        }
        return img.cgImage
    }

    private func renderCircle() -> CGImage? {
        let d = configuration.particleSize
        let renderer = imageRenderer(size: CGSize(width: d, height: d))
        let img = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).fill()
        }
        return img.cgImage
    }

    private func renderTriangle() -> CGImage? {
        let s = configuration.particleSize
        let renderer = imageRenderer(size: CGSize(width: s, height: s))
        let img = renderer.image { _ in
            UIColor.white.setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: s / 2, y: 0))
            path.addLine(to: CGPoint(x: s, y: s))
            path.addLine(to: CGPoint(x: 0, y: s))
            path.close()
            path.fill()
        }
        return img.cgImage
    }

    private func imageRenderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // MARK: - Convenience

    /// Adds a transient confetti view to `view`, fires a burst, and removes
    /// itself when finished — the simplest possible celebration call site.
    @discardableResult
    static func celebrate(
        in view: UIView,
        at point: CGPoint? = nil,
        configuration: Configuration = .default
    ) -> ConfettiView {
        let confetti = ConfettiView(configuration: configuration)
        confetti.frame = view.bounds
        confetti.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        confetti.removesSelfAfterBurst = true
        view.addSubview(confetti)
        confetti.layoutIfNeeded()
        confetti.burst(at: point)
        return confetti
    }
}
