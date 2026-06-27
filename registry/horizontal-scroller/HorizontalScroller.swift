//
//  HorizontalScroller.swift
//  Inlay — copy-paste UIKit components for iOS ("shadcn/ui for iOS")
//
//  What it is:
//  A generic, configurable horizontal scrollable list built on UICollectionView
//  with a horizontal flow layout. You supply your own item model type and a
//  cellProvider that returns a UIView per item — HorizontalScroller hosts it,
//  handles selection, optional paging, snap-to-item, peek (sliver of the next
//  item), and a center-focused scale/alpha falloff effect.
//
//  Usage:
//      let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen]
//      var config = HorizontalScroller<UIColor>.Configuration.default
//      config.itemSize = CGSize(width: 200, height: 120)
//      config.snapsToItems = true
//      config.falloff = true
//      let scroller = HorizontalScroller(items: colors, configuration: config) { color in
//          let v = UIView()
//          v.backgroundColor = color
//          v.layer.cornerRadius = 16
//          v.layer.cornerCurve = .continuous
//          return v
//      }
//      scroller.onSelect = { color, index in print("tapped", index) }
//      view.addSubview(scroller)
//      scroller.translatesAutoresizingMaskIntoConstraints = false
//      NSLayoutConstraint.activate([
//          scroller.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//          scroller.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//          scroller.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//          scroller.heightAnchor.constraint(equalToConstant: 120),
//      ])
//
//  Dependency: none (pure UIKit).
//

import UIKit

final class HorizontalScroller<Item>: UIView,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout,
    UIScrollViewDelegate {

    // MARK: Configuration

    struct Configuration {
        /// Fixed item size. `nil` enables self-sizing cells
        /// (`estimatedItemSize = UICollectionViewFlowLayout.automaticSize`).
        var itemSize: CGSize?
        /// Spacing between items.
        var spacing: CGFloat
        /// Insets around the scrollable content.
        var sectionInsets: UIEdgeInsets
        /// When true, the collection view pages by its own width.
        var isPagingEnabled: Bool
        /// When true (and not paging), snaps to the nearest item on release.
        var snapsToItems: Bool
        /// Shows a sliver of the neighbouring item by reducing the effective
        /// item width and padding the section so items stay centred.
        var peek: CGFloat
        /// When true, applies a scale + alpha falloff to items as they move
        /// away from the horizontal centre of the scroller.
        var falloff: Bool

        // Computed (not stored) because static stored properties aren't
        // allowed inside a generic type.
        static var `default`: Configuration {
            Configuration(
                itemSize: nil,
                spacing: 12,
                sectionInsets: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
                isPagingEnabled: false,
                snapsToItems: false,
                peek: 0,
                falloff: false
            )
        }
    }

    // MARK: Public API

    /// Called when an item is selected, with the item and its index.
    var onSelect: ((Item, Int) -> Void)?

    /// Replaces the backing items and reloads.
    func setItems(_ items: [Item]) {
        self.items = items
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        applyFalloffIfNeeded()
    }

    // MARK: Stored state

    private var items: [Item]
    private let configuration: Configuration
    private let cellProvider: (Item) -> UIView

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        cv.decelerationRate = .normal
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(HostCell.self, forCellWithReuseIdentifier: HostCell.reuseID)
        return cv
    }()

    // MARK: Init

    init(items: [Item],
         configuration: Configuration = .default,
         cellProvider: @escaping (Item) -> UIView) {
        self.items = items
        self.configuration = configuration
        self.cellProvider = cellProvider
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        backgroundColor = .clear

        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = configuration.spacing
        layout.minimumInteritemSpacing = configuration.spacing
        layout.sectionInset = configuration.sectionInsets
        if configuration.itemSize == nil {
            layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        }

        collectionView.isPagingEnabled = configuration.isPagingEnabled

        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFalloffIfNeeded()
    }

    // MARK: Sizing helpers

    /// Effective item width, accounting for peek (a sliver of the next item).
    private func effectiveItemSize(in collectionView: UICollectionView) -> CGSize? {
        guard var size = configuration.itemSize else { return nil }
        if configuration.peek > 0 {
            size.width = max(1, size.width - configuration.peek)
        }
        return size
    }

    // MARK: UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HostCell.reuseID, for: indexPath) as! HostCell
        let item = items[indexPath.item]
        cell.host(cellProvider(item))
        return cell
    }

    // MARK: UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if let size = effectiveItemSize(in: collectionView) {
            return size
        }
        // Self-sizing: provide a reasonable estimate; cells size themselves.
        let height = collectionView.bounds.height
            - configuration.sectionInsets.top
            - configuration.sectionInsets.bottom
        return CGSize(width: 1, height: max(1, height))
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        var insets = configuration.sectionInsets
        // With peek + snap, pad the section so the focused item sits centred.
        if configuration.peek > 0,
           let size = configuration.itemSize,
           configuration.snapsToItems || configuration.isPagingEnabled {
            let effectiveWidth = max(1, size.width - configuration.peek)
            let sidePad = max(0, (collectionView.bounds.width - effectiveWidth) / 2)
            insets.left = sidePad
            insets.right = sidePad
        }
        return insets
    }

    // MARK: UICollectionViewDelegate (selection)

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        onSelect?(item, indexPath.item)
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        applyFalloffIfNeeded()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard configuration.snapsToItems, !configuration.isPagingEnabled else { return }

        let proposedOffsetX = targetContentOffset.pointee.x
        let midX = proposedOffsetX + scrollView.bounds.width / 2

        var bestOffsetX = proposedOffsetX
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for attributes in layout.layoutAttributesForElements(
            in: CGRect(x: targetContentOffset.pointee.x,
                       y: 0,
                       width: scrollView.bounds.width,
                       height: scrollView.bounds.height)) ?? []
        where attributes.representedElementCategory == .cell {
            let distance = abs(attributes.center.x - midX)
            if distance < bestDistance {
                bestDistance = distance
                bestOffsetX = attributes.center.x - scrollView.bounds.width / 2
            }
        }

        let minOffset = -scrollView.contentInset.left
        let maxOffset = max(minOffset,
                            scrollView.contentSize.width
                                - scrollView.bounds.width
                                + scrollView.contentInset.right)
        targetContentOffset.pointee.x = min(max(bestOffsetX, minOffset), maxOffset)
    }

    // MARK: Falloff

    private func applyFalloffIfNeeded() {
        guard configuration.falloff else { return }
        let centerX = collectionView.bounds.midX + collectionView.contentOffset.x
        let maxDistance = max(1, collectionView.bounds.width / 2)

        for cell in collectionView.visibleCells {
            let distance = abs(cell.center.x - centerX)
            let ratio = min(1, distance / maxDistance)
            let scale = 1 - 0.25 * ratio
            cell.transform = CGAffineTransform(scaleX: scale, y: scale)
            cell.alpha = 1 - 0.5 * ratio
        }
    }

    // MARK: HostCell

    private final class HostCell: UICollectionViewCell {
        // Computed (not stored) because static stored properties aren't
        // allowed inside a generic type's nested type.
        static var reuseID: String { "Inlay.HorizontalScroller.HostCell" }

        private var hosted: UIView?

        override func prepareForReuse() {
            super.prepareForReuse()
            hosted?.removeFromSuperview()
            hosted = nil
            transform = .identity
            alpha = 1
        }

        func host(_ view: UIView) {
            hosted?.removeFromSuperview()
            hosted = view
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
    }
}
