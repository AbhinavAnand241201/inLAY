//
//  ParallaxHeader.swift
//  Inlay — component
//
//  A stretchy, parallax image header for a scroll view. Pulling DOWN stretches
//  and zooms the image; scrolling UP parallax-shifts it slower than the content
//  and (optionally) blurs it, dims it behind a dark gradient, and fades in an
//  overlay title. Zero wiring: it observes the scroll view's contentOffset via
//  KVO and manages the contentInset for you.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `ParallaxHeader.Configuration`.
//
//      var config = ParallaxHeader.Configuration.default
//      config.height = 280
//      config.minHeight = 0          // fully scrolls away
//      config.blurOnCollapse = true
//
//      let title = UILabel()
//      title.text = "Yosemite"
//      title.font = .systemFont(ofSize: 28, weight: .bold)
//      title.textColor = .white
//      config.titleView = title       // fades in as the header collapses
//
//      let header = ParallaxHeader(image: UIImage(named: "cover"), configuration: config)
//      header.attach(to: tableView)   // any UIScrollView / UITableView / UICollectionView
//
//      // header.detach()             // when you're done (also runs on deinit)
//
//  Dependency: none
//

import UIKit

final class ParallaxHeader: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Resting height of the header.
        var height: CGFloat = 280
        /// Collapsed floor. The header never shrinks below this while scrolling
        /// up. `0` lets it scroll entirely off-screen.
        var minHeight: CGFloat = 0
        /// How much slower the image moves than the content as you scroll up,
        /// `0...1`. `0` pins the image (no parallax); `1` matches the content.
        /// Lower values feel deeper.
        var parallaxFactor: CGFloat = 0.5
        /// Stretch + zoom the image when the user pulls down past the top.
        var stretchOnPull: Bool = true
        /// Maximum extra scale applied at full stretch (e.g. `0.6` = up to 1.6x).
        var maxStretchScale: CGFloat = 0.6
        /// Cross-fade a blur over the image as it collapses.
        var blurOnCollapse: Bool = true
        /// Blur style used when `blurOnCollapse` is on.
        var blurStyle: UIBlurEffect.Style = .systemThinMaterialDark
        /// How far through the collapse (0 = resting, 1 = fully collapsed) the
        /// blur reaches full strength.
        var blurRampEnd: CGFloat = 0.85
        /// Paint a bottom-anchored dark gradient over the image for legible
        /// titles regardless of the photo.
        var overlayGradient: Bool = true
        /// Fraction of the header height the gradient occupies, `0...1`.
        var gradientHeightFraction: CGFloat = 0.55
        /// Peak opacity of the gradient's darkest stop.
        var gradientMaxAlpha: CGFloat = 0.55
        /// Content mode for the image.
        var contentMode: UIView.ContentMode = .scaleAspectFill
        /// Background shown behind the image while it stretches/zooms.
        var backgroundColor: UIColor = .secondarySystemBackground
        /// A view (typically a title) faded in as the header collapses. It is
        /// pinned to the bottom of the header, above the gradient.
        var titleView: UIView?
        /// How far through the collapse the title reaches full opacity.
        var titleFadeStart: CGFloat = 0.45
        var titleFadeEnd: CGFloat = 0.95
        /// Inset of the title view from the header's bottom + leading edges.
        var titleInset: UIEdgeInsets = .init(top: 0, left: 20, bottom: 20, right: 20)

        static let `default` = Configuration()
    }

    // MARK: - Stored properties

    private let configuration: Configuration
    private let imageView = UIImageView()
    private var blurView: UIVisualEffectView?
    private var gradientLayer: CAGradientLayer?

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    /// The top inset we added, so we can restore it cleanly on detach.
    private var addedTopInset: CGFloat = 0

    // MARK: - Init

    init(image: UIImage?, configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = configuration.backgroundColor
        clipsToBounds = true

        imageView.image = image
        imageView.contentMode = configuration.contentMode
        imageView.clipsToBounds = true
        addSubview(imageView)

        if configuration.blurOnCollapse {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: configuration.blurStyle))
            blur.alpha = 0
            blur.isUserInteractionEnabled = false
            addSubview(blur)
            blurView = blur
        }

        if configuration.overlayGradient {
            let gradient = CAGradientLayer()
            gradient.colors = [
                UIColor.black.withAlphaComponent(0).cgColor,
                UIColor.black.withAlphaComponent(configuration.gradientMaxAlpha).cgColor,
            ]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(gradient)
            gradientLayer = gradient
        }

        if let title = configuration.titleView {
            title.alpha = 0
            addSubview(title)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { detach() }

    // MARK: - Attachment

    /// Inserts the header into `scrollView`, reserves space via `contentInset`,
    /// and starts observing scroll position. Safe to call once.
    func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView

        translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(self)

        // Reserve room at the top for the header.
        let inset = configuration.height
        scrollView.contentInset.top += inset
        addedTopInset = inset
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)

        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            self?.layout(for: sv)
        }
        layout(for: scrollView)
    }

    /// Stops observing and restores the inset we added. Idempotent.
    func detach() {
        observation?.invalidate()
        observation = nil
        if let sv = scrollView, addedTopInset != 0 {
            sv.contentInset.top -= addedTopInset
        }
        addedTopInset = 0
        scrollView = nil
        removeFromSuperview()
    }

    // MARK: - Scroll-driven layout

    /// Exposed so a host can drive layout manually (e.g. from
    /// `scrollViewDidScroll(_:)`) if it prefers not to rely on KVO. With
    /// `attach(to:)` this is invoked automatically.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layout(for: scrollView)
    }

    private func layout(for scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }

        let cfg = configuration
        // Distance from the natural top of the content. Negative = pulled down.
        let offsetFromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top

        if offsetFromTop < 0, cfg.stretchOnPull {
            // ── Pulled down: anchor at top, grow downward, zoom the image. ──
            let pull = -offsetFromTop
            let stretchedHeight = cfg.height + pull
            frame = CGRect(x: 0, y: -stretchedHeight, width: width, height: stretchedHeight)

            let progress = min(pull / cfg.height, 1)
            let scale = 1 + progress * cfg.maxStretchScale
            // Grow the image view to fill, scale-zoom from its centre.
            imageView.frame = bounds
            imageView.transform = CGAffineTransform(scaleX: scale, y: scale)

            blurView?.alpha = 0
            setTitleAlpha(0)
        } else {
            // ── Resting or scrolled up: parallax-shift + collapse. ──
            let collapse = max(offsetFromTop, 0)
            // Header's on-screen height as it collapses toward minHeight.
            let visibleHeight = max(cfg.height - collapse, cfg.minHeight)

            // Parallax: the header origin moves up slower than the content.
            // At parallaxFactor 0 it stays pinned; at 1 it scrolls with content.
            let originY = -collapse * cfg.parallaxFactor
            frame = CGRect(x: 0, y: originY, width: width, height: visibleHeight)

            imageView.transform = .identity
            imageView.frame = bounds

            // Collapse progress 0…1 over the scrollable header range.
            let range = max(cfg.height - cfg.minHeight, 1)
            let progress = min(collapse / range, 1)

            if let blur = blurView {
                let denom = max(cfg.blurRampEnd, 0.0001)
                blur.frame = bounds
                blur.alpha = min(progress / denom, 1)
            }

            setTitleAlpha(titleAlpha(for: progress))
        }

        layoutOverlay()
    }

    private func titleAlpha(for progress: CGFloat) -> CGFloat {
        let start = configuration.titleFadeStart
        let end = max(configuration.titleFadeEnd, start + 0.0001)
        return min(max((progress - start) / (end - start), 0), 1)
    }

    private func setTitleAlpha(_ alpha: CGFloat) {
        configuration.titleView?.alpha = alpha
    }

    /// Re-flows the gradient layer and title view to the current bounds.
    private func layoutOverlay() {
        if let gradient = gradientLayer {
            let h = bounds.height * configuration.gradientHeightFraction
            gradient.frame = CGRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        }
        if let title = configuration.titleView {
            let inset = configuration.titleInset
            let available = bounds.width - inset.left - inset.right
            let target = title.systemLayoutSizeFitting(
                CGSize(width: available, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel)
            let size = CGSize(width: min(target.width, available), height: target.height)
            title.frame = CGRect(
                x: inset.left,
                y: bounds.height - inset.bottom - size.height,
                width: max(size.width, available),
                height: size.height)
        }
    }
}
