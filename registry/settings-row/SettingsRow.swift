//
//  SettingsRow.swift
//  Inlay — component
//
//  A polished settings list row: an SF Symbol in a rounded color tile, a title
//  with optional subtitle, and a trailing accessory (chevron, value, or switch).
//  Springy press feedback and haptics. Drop several into a vertical stack to
//  build a settings screen.
//
//  ── How to use ────────────────────────────────────────────────────────────
//      let row = SettingsRow(
//          model: .init(icon: UIImage(systemName: "bell.badge.fill"),
//                       title: "Notifications",
//                       subtitle: "Sounds, badges, banners",
//                       accessory: .chevron)) {
//          print("open notifications")
//      }
//      let stack = UIStackView(arrangedSubviews: [row])
//      stack.axis = .vertical
//      stack.spacing = 10
//
//      // A switch row:
//      let toggle = SettingsRow(model: .init(
//          icon: UIImage(systemName: "moon.fill"),
//          title: "Dark Mode", accessory: .toggle(true)))
//      toggle.onToggle = { isOn in print("dark mode \(isOn)") }
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SettingsRow: UIControl {

    // MARK: - Accessory + Model

    enum Accessory {
        case none
        case chevron
        case value(String)
        case toggle(Bool)
    }

    struct Model {
        var icon: UIImage?
        var title: String
        var subtitle: String?
        var accessory: Accessory

        init(icon: UIImage?, title: String,
             subtitle: String? = nil, accessory: Accessory = .chevron) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.accessory = accessory
        }
    }

    // MARK: - Configuration

    struct Configuration {
        var iconTint: UIColor = .white
        var iconBackground: UIColor = .tintColor
        var iconCornerRadius: CGFloat = 8
        var iconSize: CGFloat = 30
        var rowCornerRadius: CGFloat = 14
        var background: UIColor = .secondarySystemGroupedBackground
        var highlight: UIColor = .systemFill
        var animation: Inlay.Spring = .snappy
        var hapticsEnabled: Bool = true

        static let `default` = Configuration()
    }

    // MARK: - Callbacks

    var onTap: (() -> Void)?
    var onToggle: ((Bool) -> Void)?

    // MARK: - State

    private let configuration: Configuration
    private let model: Model

    private let container = UIView()
    private let iconTile = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private lazy var switchControl = UISwitch()

    // MARK: - Init

    init(model: Model, configuration: Configuration = .default, onTap: (() -> Void)? = nil) {
        self.model = model
        self.configuration = configuration
        self.onTap = onTap
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.model = Model(icon: nil, title: "")
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = configuration.background
        container.layer.cornerRadius = configuration.rowCornerRadius
        container.layer.cornerCurve = .continuous
        container.isUserInteractionEnabled = false
        addSubview(container)

        let icon = makeIconTile()
        let text = makeTextStack()
        let accessory = makeAccessory()

        let row = UIStackView(arrangedSubviews: [icon, text, accessory].compactMap { $0 })
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false      // switch handled separately
        container.addSubview(row)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),

            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])

        // The switch needs its own touch handling above the row's.
        if case .toggle = model.accessory {
            switchControl.isUserInteractionEnabled = true
        } else {
            addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        }
    }

    private func makeIconTile() -> UIView {
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.backgroundColor = configuration.iconBackground
        iconTile.layer.cornerRadius = configuration.iconCornerRadius
        iconTile.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = configuration.iconTint
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: configuration.iconSize * 0.55, weight: .semibold)
        iconView.image = model.icon
        iconTile.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: configuration.iconSize),
            iconTile.heightAnchor.constraint(equalToConstant: configuration.iconSize),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
        ])
        return iconTile
    }

    private func makeTextStack() -> UIView {
        titleLabel.text = model.title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        let stack = UIStackView(arrangedSubviews: [titleLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 1

        if let subtitle = model.subtitle {
            subtitleLabel.text = subtitle
            subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
            subtitleLabel.adjustsFontForContentSizeCategory = true
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 1
            stack.addArrangedSubview(subtitleLabel)
        }
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func makeAccessory() -> UIView? {
        switch model.accessory {
        case .none:
            return nil
        case .chevron:
            return makeChevron()
        case .value(let text):
            let label = UILabel()
            label.text = text
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .secondaryLabel
            let stack = UIStackView(arrangedSubviews: [label, makeChevron()])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 6
            return stack
        case .toggle(let isOn):
            switchControl.isOn = isOn
            switchControl.onTintColor = configuration.iconBackground
            switchControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            return switchControl
        }
    }

    private func makeChevron() -> UIImageView {
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        return chevron
    }

    // MARK: - Interaction

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.container.backgroundColor =
                    self.isHighlighted ? self.configuration.highlight : self.configuration.background
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }

    @objc private func handleTap() {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onTap?()
    }

    @objc private func switchChanged() {
        if configuration.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onToggle?(switchControl.isOn)
    }
}
