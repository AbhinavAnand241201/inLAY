//
//  SettingsScreen.swift
//  Inlay — component (composite)
//
//  A drop-in, model-driven settings UI: inset-grouped cards, SF Symbol icons in
//  rounded color tiles, and the five row types you actually need — toggle,
//  disclosure, value, button, and slider. Built on top of the `vertical-list`
//  component (its scrolling + staggered entrance engine), which is itself built
//  on spring-animator. This is the reference example of a registry component
//  that depends on another registry component.
//
//      let screen = SettingsScreen(sections: [
//          .init(header: "General", rows: [
//              .toggle(icon: UIImage(systemName: "moon.fill"), iconTint: .systemIndigo,
//                      title: "Dark Mode", isOn: true) { on in print("dark:", on) },
//              .disclosure(icon: UIImage(systemName: "bell.fill"), iconTint: .systemRed,
//                          title: "Notifications", subtitle: "Sounds, badges") { print("open") },
//              .value(icon: UIImage(systemName: "globe"), iconTint: .systemBlue,
//                     title: "Language", value: "English") { print("pick language") },
//          ]),
//          .init(header: "Account", footer: "Signing out clears local data.", rows: [
//              .slider(icon: UIImage(systemName: "speaker.wave.2.fill"), iconTint: .systemPink,
//                      title: "Volume", value: 0.6, minValue: 0, maxValue: 1) { v in print(v) },
//              .button(icon: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
//                      title: "Sign Out", destructive: true) { print("sign out") },
//          ]),
//      ])
//      screen.translatesAutoresizingMaskIntoConstraints = false
//      view.addSubview(screen)   // pin to edges
//
//  Dependency: vertical-list (VerticalList.swift), spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SettingsScreen: UIView {

    // MARK: - Configuration

    struct Configuration {
        /// Tint for interactive controls (switches, sliders, default buttons).
        var accentColor: UIColor = .tintColor
        /// Minimum height of a row.
        var rowHeight: CGFloat = 52
        /// Corner radius of each grouped card.
        var groupCornerRadius: CGFloat = 12
        /// Shape of the leading icon tile.
        var iconShape: IconShape = .roundedSquare(cornerRadius: 7)
        /// Horizontal inset of the cards from the screen edges.
        var horizontalInset: CGFloat = 16
        /// Spring used by the underlying list's entrance + control feedback.
        var animation: Inlay.Spring = .lively

        enum IconShape {
            case roundedSquare(cornerRadius: CGFloat)
            case circle
        }

        static let `default` = Configuration()
    }

    // MARK: - Model

    struct Section {
        var header: String?
        var footer: String?
        var rows: [Row]

        init(header: String? = nil, footer: String? = nil, rows: [Row]) {
            self.header = header
            self.footer = footer
            self.rows = rows
        }
    }

    enum Row {
        case toggle(icon: UIImage?, iconTint: UIColor? = nil, title: String,
                    isOn: Bool, onChange: (Bool) -> Void)
        case disclosure(icon: UIImage?, iconTint: UIColor? = nil, title: String,
                        subtitle: String? = nil, onTap: () -> Void)
        case value(icon: UIImage?, iconTint: UIColor? = nil, title: String,
                   value: String, onTap: (() -> Void)? = nil)
        case button(icon: UIImage? = nil, iconTint: UIColor? = nil, title: String,
                    destructive: Bool = false, onTap: () -> Void)
        case slider(icon: UIImage?, iconTint: UIColor? = nil, title: String,
                    value: Float, minValue: Float = 0, maxValue: Float = 1,
                    onChange: (Float) -> Void)
    }

    // MARK: - Internal flattened model

    private enum Position { case top, middle, bottom, single }

    private enum Entry {
        case header(String)
        case footer(String)
        case row(Row, Position)
        case spacer(CGFloat)
    }

    // MARK: - Private

    private let configuration: Configuration
    private var sections: [Section]
    private var list: VerticalList<Entry>!

    // MARK: - Init

    init(sections: [Section], configuration: Configuration = .default) {
        self.configuration = configuration
        self.sections = sections
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.configuration = .default
        self.sections = []
        super.init(frame: .zero)
        setUp()
    }

    // MARK: - Public

    func setSections(_ sections: [Section]) {
        self.sections = sections
        list.setItems(flatten(sections))
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemGroupedBackground

        var listConfig = VerticalList<Entry>.Configuration.default
        listConfig.showsSeparators = false          // we draw our own, per-card
        listConfig.insetGroupedCards = false         // we style our own cards
        listConfig.spacing = 0
        listConfig.animation = configuration.animation
        listConfig.staggeredEntrance = true

        list = VerticalList<Entry>(
            items: flatten(sections),
            configuration: listConfig
        ) { [weak self] entry in
            self?.makeView(for: entry) ?? UIView()
        }
        list.translatesAutoresizingMaskIntoConstraints = false
        addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: topAnchor),
            list.bottomAnchor.constraint(equalTo: bottomAnchor),
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Flattening

    private func flatten(_ sections: [Section]) -> [Entry] {
        var entries: [Entry] = []
        for (i, section) in sections.enumerated() {
            if i == 0 { entries.append(.spacer(12)) }
            if let header = section.header { entries.append(.header(header)) }
            for (j, row) in section.rows.enumerated() {
                let position: Position
                if section.rows.count == 1 { position = .single }
                else if j == 0 { position = .top }
                else if j == section.rows.count - 1 { position = .bottom }
                else { position = .middle }
                entries.append(.row(row, position))
            }
            if let footer = section.footer { entries.append(.footer(footer)) }
            entries.append(.spacer(section.footer == nil ? 22 : 8))
        }
        return entries
    }

    // MARK: - View building

    private func makeView(for entry: Entry) -> UIView {
        switch entry {
        case .spacer(let height):
            let v = UIView()
            v.backgroundColor = .clear
            v.heightAnchor.constraint(equalToConstant: height).isActive = true
            return v
        case .header(let text):
            return makeSectionLabel(text.uppercased(), color: .secondaryLabel, top: 4, bottom: 6)
        case .footer(let text):
            return makeSectionLabel(text, color: .secondaryLabel, top: 6, bottom: 4)
        case .row(let row, let position):
            return RowView(row: row, position: position, configuration: configuration)
        }
    }

    private func makeSectionLabel(_ text: String, color: UIColor,
                                  top: CGFloat, bottom: CGFloat) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        let inset = configuration.horizontalInset + 4
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
        ])
        return container
    }

    // MARK: - Row view

    private final class RowView: UIView {

        private let row: Row
        private let position: Position
        private let configuration: Configuration
        private let card = UIView()
        private let separator = UIView()

        init(row: Row, position: Position, configuration: Configuration) {
            self.row = row
            self.position = position
            self.configuration = configuration
            super.init(frame: .zero)
            build()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

        private func build() {
            backgroundColor = .clear

            card.backgroundColor = .secondarySystemGroupedBackground
            card.layer.cornerCurve = .continuous
            card.layer.cornerRadius = configuration.groupCornerRadius
            card.layer.maskedCorners = maskedCorners(for: position)
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)

            let inset = configuration.horizontalInset
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.bottomAnchor.constraint(equalTo: bottomAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            ])

            // Leading icon tile (optional).
            let content = UIStackView()
            content.axis = .horizontal
            content.alignment = .center
            content.spacing = 12
            content.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                card.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.rowHeight),
            ])

            if let icon = icon(for: row) {
                content.addArrangedSubview(makeIconTile(icon, tint: iconTint(for: row)))
            }

            // Title (+ subtitle) column.
            let titleStack = UIStackView()
            titleStack.axis = .vertical
            titleStack.spacing = 1
            let titleLabel = UILabel()
            titleLabel.text = title(for: row)
            titleLabel.font = .preferredFont(forTextStyle: .body)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.textColor = titleColor(for: row)
            titleStack.addArrangedSubview(titleLabel)
            if case let .disclosure(_, _, _, subtitle, _) = row, let subtitle {
                let sub = UILabel()
                sub.text = subtitle
                sub.font = .preferredFont(forTextStyle: .footnote)
                sub.adjustsFontForContentSizeCategory = true
                sub.textColor = .secondaryLabel
                titleStack.addArrangedSubview(sub)
            }
            content.addArrangedSubview(titleStack)
            content.addArrangedSubview(UIView())   // flexible spacer

            // Trailing accessory.
            if let accessory = makeAccessory(for: row) {
                content.addArrangedSubview(accessory)
            }

            // Hairline separator for non-last rows.
            if position == .top || position == .middle {
                separator.backgroundColor = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(separator)
                let leading: CGFloat = icon(for: row) == nil ? 14 : 14 + 28 + 12
                NSLayoutConstraint.activate([
                    separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
                    separator.bottomAnchor.constraint(equalTo: card.bottomAnchor),
                    separator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leading),
                    separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                ])
            }

            // Whole-row tap for disclosure / value / button rows.
            switch row {
            case .disclosure, .value, .button:
                let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
                card.addGestureRecognizer(tap)
            case .toggle, .slider:
                break
            }
        }

        // MARK: Accessory builders

        private func makeAccessory(for row: Row) -> UIView? {
            switch row {
            case let .toggle(_, _, _, isOn, _):
                let toggle = UISwitch()
                toggle.isOn = isOn
                toggle.onTintColor = configuration.accentColor
                toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
                return toggle
            case .disclosure:
                return makeChevron()
            case let .value(_, _, _, value, onTap):
                let stack = UIStackView()
                stack.axis = .horizontal
                stack.alignment = .center
                stack.spacing = 6
                let valueLabel = UILabel()
                valueLabel.text = value
                valueLabel.font = .preferredFont(forTextStyle: .body)
                valueLabel.textColor = .secondaryLabel
                stack.addArrangedSubview(valueLabel)
                if onTap != nil { stack.addArrangedSubview(makeChevron()) }
                return stack
            case .button:
                return nil
            case let .slider(_, _, _, value, minValue, maxValue, _):
                let slider = UISlider()
                slider.minimumValue = minValue
                slider.maximumValue = maxValue
                slider.value = value
                slider.minimumTrackTintColor = configuration.accentColor
                slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
                slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
                slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
                return slider
            }
        }

        private func makeChevron() -> UIImageView {
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .tertiaryLabel
            chevron.contentMode = .scaleAspectFit
            chevron.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .footnote),
                                                         scale: .small)
            return chevron
        }

        private func makeIconTile(_ image: UIImage, tint: UIColor) -> UIView {
            let tile = UIView()
            tile.backgroundColor = tint
            tile.layer.cornerCurve = .continuous
            tile.translatesAutoresizingMaskIntoConstraints = false
            let side: CGFloat = 28
            switch configuration.iconShape {
            case .roundedSquare(let r): tile.layer.cornerRadius = r
            case .circle: tile.layer.cornerRadius = side / 2
            }
            let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
            imageView.tintColor = .white
            imageView.contentMode = .scaleAspectFit
            imageView.preferredSymbolConfiguration = .init(pointSize: 15, weight: .semibold)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(imageView)
            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: side),
                tile.heightAnchor.constraint(equalToConstant: side),
                imageView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            ])
            return tile
        }

        // MARK: Actions

        @objc private func rowTapped() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Inlay.SpringAnimator.animate(configuration.animation) {
                self.card.backgroundColor = .tertiarySystemGroupedBackground
            } completion: {
                Inlay.SpringAnimator.animate(self.configuration.animation) {
                    self.card.backgroundColor = .secondarySystemGroupedBackground
                }
            }
            switch row {
            case let .disclosure(_, _, _, _, onTap): onTap()
            case let .value(_, _, _, _, onTap): onTap?()
            case let .button(_, _, _, _, onTap): onTap()
            default: break
            }
        }

        @objc private func switchChanged(_ sender: UISwitch) {
            if case let .toggle(_, _, _, _, onChange) = row { onChange(sender.isOn) }
        }

        @objc private func sliderChanged(_ sender: UISlider) {
            if case let .slider(_, _, _, _, _, _, onChange) = row { onChange(sender.value) }
        }

        // MARK: Row introspection

        private func icon(for row: Row) -> UIImage? {
            switch row {
            case let .toggle(icon, _, _, _, _): return icon
            case let .disclosure(icon, _, _, _, _): return icon
            case let .value(icon, _, _, _, _): return icon
            case let .button(icon, _, _, _, _): return icon
            case let .slider(icon, _, _, _, _, _, _): return icon
            }
        }

        private func iconTint(for row: Row) -> UIColor {
            let explicit: UIColor?
            switch row {
            case let .toggle(_, t, _, _, _): explicit = t
            case let .disclosure(_, t, _, _, _): explicit = t
            case let .value(_, t, _, _, _): explicit = t
            case let .button(_, t, _, _, _): explicit = t
            case let .slider(_, t, _, _, _, _, _): explicit = t
            }
            return explicit ?? configuration.accentColor
        }

        private func title(for row: Row) -> String {
            switch row {
            case let .toggle(_, _, title, _, _): return title
            case let .disclosure(_, _, title, _, _): return title
            case let .value(_, _, title, _, _): return title
            case let .button(_, _, title, _, _): return title
            case let .slider(_, _, title, _, _, _, _): return title
            }
        }

        private func titleColor(for row: Row) -> UIColor {
            if case let .button(_, _, _, destructive, _) = row {
                return destructive ? .systemRed : configuration.accentColor
            }
            return .label
        }

        private func maskedCorners(for position: Position) -> CACornerMask {
            switch position {
            case .single:
                return [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                        .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .top:
                return [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            case .bottom:
                return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .middle:
                return []
            }
        }
    }
}
