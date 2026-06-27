//
//  SearchBar.swift
//  Inlay — component
//
//  A rounded search field wrapping a `UITextField`, with a leading icon, a
//  glass (blur) or solid background, an animated focus state that lifts the
//  shadow and reveals a trailing "Cancel" button, plus debounced text-change,
//  submit, and cancel callbacks.
//
//  ── How to use ────────────────────────────────────────────────────────────
//  Paste this file into your project. It runs as-is, no setup required.
//  Everything is customized through `SearchBar.Configuration`.
//
//      let search = SearchBar()
//      search.onTextChange = { query in print("typing:", query) }
//      search.onSubmit     = { query in print("submit:", query) }
//      search.onCancel     = { print("cancelled") }
//      view.addSubview(search)
//      NSLayoutConstraint.activate([
//          search.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
//          search.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
//          search.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
//      ])
//
//  Dependency: spring-animator (Inlay+SpringAnimator.swift)
//

import UIKit

final class SearchBar: UIView {

    // MARK: - Configuration

    /// All visual + behavioural knobs. Nested so it can never collide with
    /// another component's `Configuration`.
    struct Configuration {
        /// Placeholder shown when the field is empty.
        var placeholder: String = "Search"
        /// Leading glyph. Defaults to the system magnifying glass.
        var icon: UIImage? = UIImage(systemName: "magnifyingglass")
        /// Corner radius of the field. Large values read as fully rounded.
        var cornerRadius: CGFloat = 12
        /// Background appearance.
        var background: Background = .solid(.secondarySystemBackground)
        /// Tint for the caret, cancel button, and clear button.
        var accentColor: UIColor = .tintColor
        /// Whether focusing reveals a trailing "Cancel" button.
        var showsCancel: Bool = true
        /// Whether the system clear (✕) button appears while editing.
        var clearButton: Bool = true
        /// Spring used for focus / cancel transitions. (Shared design token.)
        var animation: Inlay.Spring = .snappy
        /// Debounce window applied to `onTextChange`, in seconds.
        var debounceInterval: TimeInterval = 0.3

        enum Background {
            case glass(UIBlurEffect.Style)
            case solid(UIColor)
        }

        static let `default` = Configuration()
    }

    // MARK: - Callbacks

    /// Fired after the user pauses typing for `debounceInterval` seconds.
    var onTextChange: ((String) -> Void)?
    /// Fired when the user taps return.
    var onSubmit: ((String) -> Void)?
    /// Fired when the user taps the "Cancel" button.
    var onCancel: (() -> Void)?

    /// Convenience accessor / mutator for the current query.
    var text: String {
        get { field.text ?? "" }
        set { field.text = newValue }
    }

    // MARK: - Private state

    private let configuration: Configuration
    private let container = UIView()
    private var backgroundView = UIView()
    private let iconView = UIImageView()
    private let field = UITextField()
    private let cancelButton = UIButton(type: .system)

    private var fieldTrailingConstraint: NSLayoutConstraint!
    private var cancelWidthConstraint: NSLayoutConstraint!
    private var debounceWorkItem: DispatchWorkItem?

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

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // Outer view carries the shadow and must NOT clip.
        setUpShadow()

        // Inner container clips the corner radius + background.
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = configuration.cornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setUpBackground()
        setUpContent()
        setUpCancel()
    }

    private func setUpShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0       // raised on focus
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    private func setUpBackground() {
        switch configuration.background {
        case .glass(let style):
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        case .solid(let color):
            let view = UIView()
            view.backgroundColor = color
            backgroundView = view
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        container.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func setUpContent() {
        iconView.image = configuration.icon
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        field.placeholder = configuration.placeholder
        field.textColor = .label
        field.tintColor = configuration.accentColor
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .search
        field.clearButtonMode = configuration.clearButton ? .whileEditing : .never
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        container.addSubview(iconView)
        container.addSubview(field)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
    }

    private func setUpCancel() {
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(configuration.accentColor, for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.titleLabel?.lineBreakMode = .byClipping
        cancelButton.alpha = 0
        cancelButton.clipsToBounds = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)

        // Collapsed by default; expands on focus when `showsCancel` is true.
        cancelWidthConstraint = cancelButton.widthAnchor.constraint(equalToConstant: 0)

        // The field's trailing pins to the container until cancel reveals,
        // then re-pins inside while the cancel button sits to the right.
        fieldTrailingConstraint = field.trailingAnchor.constraint(
            equalTo: container.trailingAnchor, constant: -12
        )

        NSLayoutConstraint.activate([
            cancelWidthConstraint,
            fieldTrailingConstraint,
            cancelButton.leadingAnchor.constraint(equalTo: container.trailingAnchor, constant: 8),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    // MARK: - Focus transitions

    private func setFocused(_ focused: Bool) {
        guard configuration.showsCancel else {
            raiseShadow(focused)
            return
        }
        let cancelWidth = focused ? cancelButton.intrinsicContentSize.width + 8 : 0
        // Make room on the trailing side for the cancel button.
        fieldTrailingConstraint.constant = focused ? -12 - cancelWidth : -12
        cancelWidthConstraint.constant = cancelWidth

        raiseShadow(focused)
        Inlay.SpringAnimator.animate(configuration.animation) {
            self.cancelButton.alpha = focused ? 1 : 0
            self.layoutIfNeeded()
        }
    }

    private func raiseShadow(_ raised: Bool) {
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = layer.shadowOpacity
        animation.toValue = raised ? 0.18 : 0
        animation.duration = configuration.animation.duration
        layer.add(animation, forKey: "shadowOpacity")
        layer.shadowOpacity = raised ? 0.18 : 0
    }

    // MARK: - Actions

    @objc private func editingChanged() {
        scheduleDebouncedChange(field.text ?? "")
    }

    private func scheduleDebouncedChange(_ value: String) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onTextChange?(value)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + configuration.debounceInterval,
            execute: work
        )
    }

    @objc private func cancelTapped() {
        debounceWorkItem?.cancel()
        field.text = ""
        field.resignFirstResponder()
        onCancel?()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Shadow path tracks the field shape for crisp, performant shadows.
        layer.shadowPath = UIBezierPath(
            roundedRect: container.frame,
            cornerRadius: configuration.cornerRadius
        ).cgPath
    }
}

// MARK: - UITextFieldDelegate

extension SearchBar: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        setFocused(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        setFocused(false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        debounceWorkItem?.cancel()
        onSubmit?(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
