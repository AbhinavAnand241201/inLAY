import UIKit

/// Exercises the FloatingToolbar component and its config-driven variants.
/// Mirrors docs/FLOATING_TOOLBAR_TEST.md: entrance animation, press feedback,
/// selection highlight, dark mode, and the three manifest variants.
final class DemoViewController: UIViewController {

    private var toolbar: FloatingToolbar?
    private let variantControl = UISegmentedControl(items: ["Glass", "Solid", "Tinted"])

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Inlay — Floating Toolbar"

        // A bit of sample content so the glass blur has something to blur.
        let label = UILabel()
        label.text = "Inlay"
        label.font = .systemFont(ofSize: 96, weight: .heavy)
        label.textColor = .quaternaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        variantControl.selectedSegmentIndex = 0
        variantControl.translatesAutoresizingMaskIntoConstraints = false
        variantControl.addTarget(self, action: #selector(variantChanged), for: .valueChanged)
        view.addSubview(variantControl)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            variantControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            variantControl.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])

        installToolbar(configuration: configuration(for: 0))
    }

    @objc private func variantChanged() {
        toolbar?.removeFromSuperview()
        installToolbar(configuration: configuration(for: variantControl.selectedSegmentIndex))
    }

    private func configuration(for index: Int) -> FloatingToolbar.Configuration {
        var config = FloatingToolbar.Configuration.default
        switch index {
        case 1: // Solid
            config.background = .solid(.secondarySystemBackground)
        case 2: // Tinted
            config.accentColor = .systemPurple
            config.animation = .playful
        default: // Glass
            config.background = .glass(.systemThinMaterial)
        }
        return config
    }

    private func installToolbar(configuration: FloatingToolbar.Configuration) {
        let toolbar = FloatingToolbar(items: [
            .init(icon: UIImage(systemName: "house.fill"))      { print("home") },
            .init(icon: UIImage(systemName: "magnifyingglass")) { print("search") },
            .init(icon: UIImage(systemName: "bell.fill"))       { print("alerts") },
            .init(icon: UIImage(systemName: "person.fill"))     { print("profile") },
        ], configuration: configuration)
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        self.toolbar = toolbar
    }
}
