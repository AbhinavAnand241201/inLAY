//
//  VerticalList.swift
//  Inlay — component
//
//  A generic, customizable vertical list built on `UICollectionView` with a
//  compositional list layout. You supply the data and a `cellProvider` that
//  returns a view per item; the list hosts it, self-sizes the row height,
//  and (optionally) plays a staggered fade-and-slide entrance.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `VerticalList.Configuration`.
//
//      let list = VerticalList<String>(items: ["One", "Two", "Three"]) { item in
//          let label = UILabel()
//          label.text = item
//          label.font = .preferredFont(forTextStyle: .body)
//          return label
//      }
//      list.onSelect = { item, index in print("tapped \(item) at \(index)") }
//      view.addSubview(list)
//      NSLayoutConstraint.activate([
//          list.topAnchor.constraint(equalTo: view.topAnchor),
//          list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//          list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//          list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class VerticalList<Item>: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Vertical spacing between rows.
        var spacing: CGFloat = 0
        /// Content insets around the whole list.
        var insets: UIEdgeInsets = .zero
        /// Whether to draw row separators.
        var showsSeparators: Bool = true
        /// When true, rows get a grouped, rounded-card background like
        /// `.insetGrouped`, with rounded top/bottom on the first/last rows.
        var insetGroupedCards: Bool = false
        /// Spring used for the entrance animation. (Shared design token.)
        var animation: Inlay.Spring = .lively
        /// Whether rows fade + slide in on first appearance.
        var staggeredEntrance: Bool = true
        /// Only the first N rows animate so long lists don't lag.
        var maxStagger: Int = 12

        init() {}

        /// Generic types can't hold static stored properties, so this is a
        /// computed default; the value is identical for every `Item`.
        static var `default`: Configuration { Configuration() }
    }

    // MARK: - Public surface

    /// Called when a row is tapped. Provides the item and its index.
    var onSelect: ((Item, Int) -> Void)?

    // MARK: - Private state

    private let configuration: Configuration
    private var items: [Item]
    private let cellProvider: (Item) -> UIView
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var animatedIndexPaths: Set<IndexPath> = []
    private var delegateProxy: DelegateProxy!

    // MARK: - Init

    init(
        items: [Item],
        configuration: Configuration = .default,
        cellProvider: @escaping (Item) -> UIView
    ) {
        self.configuration = configuration
        self.items = items
        self.cellProvider = cellProvider
        super.init(frame: .zero)
        setUp()
        applySnapshot(animatingDifferences: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; VerticalList is programmatic only.")
    }

    // MARK: - Items

    /// Replace the list's items at runtime.
    func setItems(_ items: [Item]) {
        self.items = items
        animatedIndexPaths.removeAll()
        applySnapshot(animatingDifferences: false)
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        let layout = makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.contentInset = configuration.insets

        // A non-generic proxy carries the @objc delegate conformance, which a
        // generic class cannot. It forwards back into `self` via closures.
        delegateProxy = DelegateProxy()
        delegateProxy.didSelect = { [weak self] indexPath in
            guard let self else { return }
            self.collectionView.deselectItem(at: indexPath, animated: true)
            guard self.items.indices.contains(indexPath.item) else { return }
            self.onSelect?(self.items[indexPath.item], indexPath.item)
        }
        delegateProxy.willDisplay = { [weak self] cell, indexPath in
            self?.animateEntrance(of: cell, at: indexPath)
        }
        collectionView.delegate = delegateProxy
        if configuration.insetGroupedCards {
            collectionView.backgroundColor = .clear
        }
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<HostCell, Int> {
            [weak self] cell, indexPath, _ in
            guard let self else { return }
            let item = self.items[indexPath.item]
            cell.host(self.cellProvider(item))
            cell.applyGroupedStyle(
                enabled: self.configuration.insetGroupedCards,
                isFirst: indexPath.item == 0,
                isLast: indexPath.item == self.items.count - 1
            )
        }

        dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, identifier in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: identifier
            )
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = configuration.showsSeparators && !configuration.insetGroupedCards
        config.backgroundColor = .clear

        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            let section = NSCollectionLayoutSection.list(
                using: config,
                layoutEnvironment: environment
            )
            if let spacing = self?.configuration.spacing, spacing > 0 {
                section.interGroupSpacing = spacing
            }
            return section
        }
        return layout
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items.indices), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    // MARK: - HostCell

    /// Hosts a caller-provided view, pinned to the content view's edges.
    /// Resets its hosted subviews on reuse so cells never stack content.
    private final class HostCell: UICollectionViewCell {

        private var hostedView: UIView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            contentView.backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported.")
        }

        func host(_ view: UIView) {
            hostedView?.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            hostedView = view
        }

        func applyGroupedStyle(enabled: Bool, isFirst: Bool, isLast: Bool) {
            guard enabled else {
                backgroundColor = .clear
                contentView.layer.cornerRadius = 0
                contentView.layer.maskedCorners = []
                contentView.backgroundColor = .clear
                return
            }
            contentView.backgroundColor = .secondarySystemGroupedBackground
            contentView.layer.cornerCurve = .continuous
            contentView.clipsToBounds = true

            var corners: CACornerMask = []
            if isFirst {
                corners.insert(.layerMinXMinYCorner)
                corners.insert(.layerMaxXMinYCorner)
            }
            if isLast {
                corners.insert(.layerMinXMaxYCorner)
                corners.insert(.layerMaxXMaxYCorner)
            }
            contentView.layer.maskedCorners = corners
            contentView.layer.cornerRadius = corners.isEmpty ? 0 : 12
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            hostedView?.removeFromSuperview()
            hostedView = nil
            contentView.layer.cornerRadius = 0
            contentView.layer.maskedCorners = []
            contentView.backgroundColor = .clear
        }
    }

    // MARK: - Entrance

    private func animateEntrance(of cell: UICollectionViewCell, at indexPath: IndexPath) {
        guard configuration.staggeredEntrance else { return }
        guard !animatedIndexPaths.contains(indexPath) else { return }
        animatedIndexPaths.insert(indexPath)
        guard indexPath.item < configuration.maxStagger else { return }

        cell.alpha = 0
        cell.transform = CGAffineTransform(translationX: 0, y: 12)

        let delay = TimeInterval(indexPath.item) * 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Inlay.SpringAnimator.animate(self.configuration.animation) {
                cell.alpha = 1
                cell.transform = .identity
            }
        }
    }

    // MARK: - DelegateProxy

    /// A non-generic `NSObject` that carries the `@objc` collection-view
    /// delegate conformance (a generic class can't) and forwards events back
    /// into the owning list through closures.
    private final class DelegateProxy: NSObject, UICollectionViewDelegate {

        var didSelect: ((IndexPath) -> Void)?
        var willDisplay: ((UICollectionViewCell, IndexPath) -> Void)?

        func collectionView(
            _ collectionView: UICollectionView,
            didSelectItemAt indexPath: IndexPath
        ) {
            didSelect?(indexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            willDisplay?(cell, indexPath)
        }
    }
}
