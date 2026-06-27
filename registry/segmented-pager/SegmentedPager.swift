//
//  SegmentedPager.swift
//  Inlay — component
//
//  A header row of tab titles above a horizontally-paging content area.
//  Swiping pages and tapping tabs stay in sync, and the header indicator
//  (underline or pill) tracks the scroll offset LIVE — it interpolates its
//  position and width between adjacent tabs as you drag, the signature detail.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SegmentedPager.Configuration`.
//
//      let pager = SegmentedPager(pages: [
//          .init(title: "For You", view: forYouVC.view),
//          .init(title: "Following", view: followingVC.view),
//          .init(title: "Trending", view: trendingVC.view),
//      ])
//      pager.onChange = { index in print("page \(index)") }
//      view.addSubview(pager)
//      NSLayoutConstraint.activate([
//          pager.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
//          pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//          pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//          pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SegmentedPager: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Shape of the live indicator that tracks the active tab.
        var indicatorStyle: IndicatorStyle = .underline
        /// Tint for the indicator and the selected title.
        var accentColor: UIColor = .tintColor
        /// Appearance behind the tab header.
        var headerBackground: HeaderBackground = .clear
        /// Fixed height of the tab header row.
        var headerHeight: CGFloat = 48
        /// Font used for every tab title.
        var titleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold)
        /// Color of the currently-selected title.
        var selectedTitleColor: UIColor = .label
        /// Color of unselected titles. Interpolates toward `selectedTitleColor`.
        var titleColor: UIColor = .secondaryLabel
        /// Thickness of the underline indicator (`.underline` only).
        var indicatorHeight: CGFloat = 3
        /// Inset of the pill indicator from the tab bounds (`.pill` only).
        var indicatorInset: CGFloat = 6
        /// Equal-width tabs that fill the header. If `false`, tabs self-size and
        /// the header scrolls horizontally.
        var equalTabWidths: Bool = true
        /// Whether the paging content area rubber-bands at the edges.
        var bounces: Bool = true
        /// Horizontal padding applied around each tab title.
        var tabHorizontalPadding: CGFloat = 16
        /// Spring used for tab-tap scroll + indicator settling. (Shared token.)
        var animation: Inlay.Spring = .snappy

        /// `.underline`: a thin bar under the active tab.
        /// `.pill`: a rounded capsule behind the active tab.
        enum IndicatorStyle {
            case underline
            case pill
        }

        enum HeaderBackground {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
            case clear
        }

        static let `default` = Configuration()
    }

    // MARK: - Page

    /// One tab + its content view. The content view is laid out by the pager.
    struct Page {
        let title: String
        let view: UIView

        init(title: String, view: UIView) {
            self.title = title
            self.view = view
        }
    }

    // MARK: - Public API

    /// The active page. Settable — assigning animates the scroll + indicator.
    var selectedIndex: Int {
        get { currentIndex }
        set { select(index: newValue, animated: true, notify: true) }
    }

    /// Called whenever the active page changes (by tap or by settling a swipe).
    var onChange: ((Int) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private let pages: [Page]

    private let headerScrollView = UIScrollView()
    private let headerBackgroundView: UIView
    private let tabStack = UIStackView()
    private let indicator = UIView()

    private let contentScrollView = UIScrollView()
    private let contentStack = UIStackView()

    private var tabLabels: [UILabel] = []
    private var tabButtons: [UIControl] = []

    private var indicatorLeading: NSLayoutConstraint?
    private var indicatorWidth: NSLayoutConstraint?

    private var currentIndex = 0
    private var isProgrammaticScroll = false
    private var hasLaidOut = false

    // MARK: - Init

    init(pages: [Page], configuration: Configuration = .default) {
        self.configuration = configuration
        self.pages = pages
        self.headerBackgroundView = Self.makeBackground(configuration.headerBackground)
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.pages = []
        self.headerBackgroundView = UIView()
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        setUpHeader()
        setUpContent()
        setUpTabs()
        setUpIndicator()
    }

    private static func makeBackground(_ background: Configuration.HeaderBackground) -> UIView {
        switch background {
        case .glass(let style):
            return UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .solid(let color):
            let view = UIView()
            view.backgroundColor = color
            return view
        case .clear:
            let view = UIView()
            view.backgroundColor = .clear
            return view
        }
    }

    private func setUpHeader() {
        headerBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        headerBackgroundView.isUserInteractionEnabled = false
        addSubview(headerBackgroundView)

        headerScrollView.translatesAutoresizingMaskIntoConstraints = false
        headerScrollView.showsHorizontalScrollIndicator = false
        headerScrollView.showsVerticalScrollIndicator = false
        headerScrollView.bounces = configuration.equalTabWidths ? false : true
        headerScrollView.alwaysBounceVertical = false
        headerScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(headerScrollView)

        NSLayoutConstraint.activate([
            headerBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            headerBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBackgroundView.heightAnchor.constraint(equalToConstant: configuration.headerHeight),

            headerScrollView.topAnchor.constraint(equalTo: topAnchor),
            headerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerScrollView.heightAnchor.constraint(equalToConstant: configuration.headerHeight),
        ])
    }

    private func setUpContent() {
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.isPagingEnabled = true
        contentScrollView.showsHorizontalScrollIndicator = false
        contentScrollView.showsVerticalScrollIndicator = false
        contentScrollView.bounces = configuration.bounces
        contentScrollView.alwaysBounceVertical = false
        contentScrollView.contentInsetAdjustmentBehavior = .never
        contentScrollView.delegate = self
        addSubview(contentScrollView)

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: headerScrollView.bottomAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Pages laid side-by-side in a horizontal stack pinned to the content
        // layout guide; each page is exactly one frame wide.
        contentStack.axis = .horizontal
        contentStack.distribution = .fillEqually
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.addSubview(contentStack)

        let frameGuide = contentScrollView.frameLayoutGuide
        let contentGuide = contentScrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            contentStack.heightAnchor.constraint(equalTo: frameGuide.heightAnchor),
        ])

        for page in pages {
            let host = UIView()
            host.translatesAutoresizingMaskIntoConstraints = false
            let content = page.view
            content.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: host.topAnchor),
                content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                host.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
            ])
            contentStack.addArrangedSubview(host)
        }
    }

    private func setUpTabs() {
        tabStack.axis = .horizontal
        tabStack.alignment = .fill
        tabStack.distribution = configuration.equalTabWidths ? .fillEqually : .fill
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        headerScrollView.addSubview(tabStack)

        let frameGuide = headerScrollView.frameLayoutGuide
        let contentGuide = headerScrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            tabStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            tabStack.heightAnchor.constraint(equalTo: frameGuide.heightAnchor),
        ])
        if configuration.equalTabWidths {
            tabStack.widthAnchor.constraint(equalTo: frameGuide.widthAnchor).isActive = true
        }

        for (index, page) in pages.enumerated() {
            let control = UIControl()
            control.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = page.title
            label.font = configuration.titleFont
            label.textAlignment = .center
            label.textColor = (index == currentIndex)
                ? configuration.selectedTitleColor
                : configuration.titleColor
            label.isUserInteractionEnabled = false
            control.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                label.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                label.leadingAnchor.constraint(
                    equalTo: control.leadingAnchor,
                    constant: configuration.tabHorizontalPadding),
                label.trailingAnchor.constraint(
                    equalTo: control.trailingAnchor,
                    constant: -configuration.tabHorizontalPadding),
            ])

            control.addAction(UIAction { [weak self] _ in
                self?.handleTap(index: index)
            }, for: .touchUpInside)
            control.addTarget(self, action: #selector(tabTouchDown(_:)), for: .touchDown)
            control.addTarget(
                self,
                action: #selector(tabTouchUp(_:)),
                for: [.touchUpInside, .touchUpOutside, .touchCancel])

            tabLabels.append(label)
            tabButtons.append(control)
            tabStack.addArrangedSubview(control)
        }
    }

    private func setUpIndicator() {
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isUserInteractionEnabled = false
        indicator.layer.cornerCurve = .continuous

        switch configuration.indicatorStyle {
        case .underline:
            indicator.backgroundColor = configuration.accentColor
            indicator.layer.cornerRadius = configuration.indicatorHeight / 2
            tabStack.addSubview(indicator)
            indicatorWidth = indicator.widthAnchor.constraint(equalToConstant: 0)
            indicatorLeading = indicator.leadingAnchor.constraint(
                equalTo: tabStack.leadingAnchor, constant: 0)
            NSLayoutConstraint.activate([
                indicator.bottomAnchor.constraint(equalTo: tabStack.bottomAnchor),
                indicator.heightAnchor.constraint(equalToConstant: configuration.indicatorHeight),
                indicatorWidth!,
                indicatorLeading!,
            ])
        case .pill:
            indicator.backgroundColor = configuration.accentColor.withAlphaComponent(0.16)
            tabStack.insertSubview(indicator, at: 0)
            indicatorWidth = indicator.widthAnchor.constraint(equalToConstant: 0)
            indicatorLeading = indicator.leadingAnchor.constraint(
                equalTo: tabStack.leadingAnchor, constant: 0)
            NSLayoutConstraint.activate([
                indicator.topAnchor.constraint(
                    equalTo: tabStack.topAnchor, constant: configuration.indicatorInset),
                indicator.bottomAnchor.constraint(
                    equalTo: tabStack.bottomAnchor, constant: -configuration.indicatorInset),
                indicatorWidth!,
                indicatorLeading!,
            ])
        }
    }

    // MARK: - Interaction

    private func handleTap(index: Int) {
        guard index != currentIndex else { return }
        select(index: index, animated: true, notify: true)
    }

    @objc private func tabTouchDown(_ sender: UIControl) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc private func tabTouchUp(_ sender: UIControl) {
        Inlay.SpringAnimator.animate(configuration.animation) {
            sender.transform = .identity
        }
    }

    // MARK: - Selection

    private func select(index: Int, animated: Bool, notify: Bool) {
        guard !pages.isEmpty else { return }
        let clamped = max(0, min(index, pages.count - 1))
        let changed = clamped != currentIndex
        currentIndex = clamped

        let pageWidth = contentScrollView.bounds.width
        let target = CGPoint(x: pageWidth * CGFloat(clamped), y: 0)

        if animated, pageWidth > 0 {
            isProgrammaticScroll = true
            Inlay.SpringAnimator.animate(configuration.animation, animations: {
                self.contentScrollView.contentOffset = target
                self.updateIndicator(forOffsetX: target.x, pageWidth: pageWidth)
                self.updateTitleColors(forOffsetX: target.x, pageWidth: pageWidth)
            }, completion: { [weak self] in
                self?.isProgrammaticScroll = false
            })
        } else {
            contentScrollView.contentOffset = target
            if pageWidth > 0 {
                updateIndicator(forOffsetX: target.x, pageWidth: pageWidth)
                updateTitleColors(forOffsetX: target.x, pageWidth: pageWidth)
            }
        }

        if changed, notify { onChange?(clamped) }
        keepTabVisible(index: clamped, animated: animated)
    }

    /// Live, proportional indicator tracking: interpolate position + width
    /// between the two tabs the scroll currently sits between.
    private func updateIndicator(forOffsetX offsetX: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0, !tabButtons.isEmpty else { return }

        let progress = offsetX / pageWidth
        let lower = max(0, min(Int(floor(progress)), tabButtons.count - 1))
        let upper = max(0, min(lower + 1, tabButtons.count - 1))
        let t = progress - CGFloat(lower)

        let lowerFrame = tabButtons[lower].frame
        let upperFrame = tabButtons[upper].frame

        let x = lerp(lowerFrame.minX, upperFrame.minX, t)
        let width = lerp(lowerFrame.width, upperFrame.width, t)

        switch configuration.indicatorStyle {
        case .underline:
            indicatorLeading?.constant = x
            indicatorWidth?.constant = width
        case .pill:
            let inset = configuration.indicatorInset
            indicatorLeading?.constant = x + inset
            indicatorWidth?.constant = max(0, width - inset * 2)
            indicator.layer.cornerRadius =
                max(0, (configuration.headerHeight - inset * 2) / 2)
        }
    }

    /// Crossfade each tab's title color based on how close the scroll is to it.
    private func updateTitleColors(forOffsetX offsetX: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0 else { return }
        let progress = offsetX / pageWidth
        for (index, label) in tabLabels.enumerated() {
            let distance = min(1, abs(progress - CGFloat(index)))
            label.textColor = blend(
                configuration.selectedTitleColor,
                configuration.titleColor,
                amount: distance)
        }
    }

    private func keepTabVisible(index: Int, animated: Bool) {
        guard !configuration.equalTabWidths, index < tabButtons.count else { return }
        let frame = tabButtons[index].frame
        headerScrollView.scrollRectToVisible(frame.insetBy(dx: -24, dy: 0), animated: animated)
    }

    // MARK: - Math helpers

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func blend(_ a: UIColor, _ b: UIColor, amount: CGFloat) -> UIColor {
        let t = max(0, min(amount, 1))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        // Resolve dynamic colors against the current trait collection so dark
        // mode is honoured automatically.
        let resolvedA = a.resolvedColor(with: traitCollection)
        let resolvedB = b.resolvedColor(with: traitCollection)
        resolvedA.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        resolvedB.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: lerp(ar, br, t),
            green: lerp(ag, bg, t),
            blue: lerp(ab, bb, t),
            alpha: lerp(aa, ba, t))
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let pageWidth = contentScrollView.bounds.width
        guard pageWidth > 0 else { return }

        // On first layout (and any bounds change), pin the scroll + indicator
        // to the current page without animating.
        if !hasLaidOut {
            hasLaidOut = true
            contentScrollView.contentOffset = CGPoint(x: pageWidth * CGFloat(currentIndex), y: 0)
        }
        layoutIfNeeded()
        updateIndicator(forOffsetX: contentScrollView.contentOffset.x, pageWidth: pageWidth)
        updateTitleColors(forOffsetX: contentScrollView.contentOffset.x, pageWidth: pageWidth)
    }
}

// MARK: - UIScrollViewDelegate

extension SegmentedPager: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === contentScrollView, !isProgrammaticScroll else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let offsetX = scrollView.contentOffset.x
        updateIndicator(forOffsetX: offsetX, pageWidth: pageWidth)
        updateTitleColors(forOffsetX: offsetX, pageWidth: pageWidth)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle(scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle(scrollView) }
    }

    private func settle(_ scrollView: UIScrollView) {
        guard scrollView === contentScrollView else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let index = Int(round(scrollView.contentOffset.x / pageWidth))
        let clamped = max(0, min(index, pages.count - 1))
        guard clamped != currentIndex else { return }
        currentIndex = clamped
        keepTabVisible(index: clamped, animated: true)
        onChange?(clamped)
    }
}
