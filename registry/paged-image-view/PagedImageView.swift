//
//  PagedImageView.swift
//  Inlay — component
//
//  A swipeable image carousel: one image fills the container, swipe horizontally
//  to page through the rest, with page dots centered at the bottom showing the
//  current image. Tapping the dots jumps pages.
//
//      let carousel = PagedImageView(images: [img1, img2, img3, img4])
//      carousel.onPageChange = { index in print("now showing", index) }
//      view.addSubview(carousel)
//      // give it a frame / constraints — it fills whatever size you give it.
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class PagedImageView: UIView {

    // MARK: - Configuration

    struct Configuration {
        var cornerRadius: CGFloat = 16
        var imageContentMode: UIView.ContentMode = .scaleAspectFill
        var activeDotColor: UIColor = .label
        var inactiveDotColor: UIColor = .quaternaryLabel
        var showsPageControl: Bool = true
        /// Spring used for programmatic page jumps.
        var animation: Inlay.Spring = .snappy
        static let `default` = Configuration()
    }

    // MARK: - Public

    /// Called whenever the visible page changes (by swipe or tap).
    var onPageChange: ((Int) -> Void)?
    private(set) var currentPage = 0

    // MARK: - Private

    private let configuration: Configuration
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let pageControl = UIPageControl()
    private var imageViews: [UIImageView] = []

    // MARK: - Init

    init(images: [UIImage?] = [], configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
        setImages(images)
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = configuration.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentStack.axis = .horizontal
        contentStack.distribution = .fillEqually
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        pageControl.currentPageIndicatorTintColor = configuration.activeDotColor
        pageControl.pageIndicatorTintColor = configuration.inactiveDotColor
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        addSubview(pageControl)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Content

    func setImages(_ images: [UIImage?]) {
        for view in imageViews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        imageViews.removeAll()

        for image in images {
            let imageView = UIImageView(image: image)
            imageView.contentMode = configuration.imageContentMode
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ).isActive = true
            contentStack.addArrangedSubview(imageView)
            imageViews.append(imageView)
        }

        pageControl.numberOfPages = images.count
        pageControl.isHidden = !configuration.showsPageControl || images.count <= 1
        currentPage = 0
        pageControl.currentPage = 0
    }

    // MARK: - Paging

    func scrollToPage(_ page: Int, animated: Bool = true) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        scrollView.setContentOffset(CGPoint(x: CGFloat(page) * width, y: 0), animated: animated)
    }

    @objc private func pageControlChanged() {
        scrollToPage(pageControl.currentPage, animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension PagedImageView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / width).rounded())
        guard page != currentPage else { return }
        currentPage = page
        pageControl.currentPage = page
        onPageChange?(page)
    }
}
