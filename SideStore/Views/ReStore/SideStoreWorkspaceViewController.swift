#if os(iOS)
import UIKit
import SwiftUI

@MainActor
final class SideStoreWorkspaceViewController: UIViewController {
    private let controllers: [UIViewController]
    private let content = UIView()
    private let navigation = UIStackView()
    private var buttons: [UIButton] = []
    private var visibleController: UIViewController?

    init(controllers: [UIViewController]) {
        self.controllers = controllers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(controllers:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        navigation.axis = .horizontal
        navigation.spacing = 8
        navigation.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(navigation)
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 44),
            navigation.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            navigation.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            navigation.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            navigation.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            navigation.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            content.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let titles = ["News", "Sources", "Browse", "My Apps", "Settings", "Signing"]
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.tinted()
            configuration.title = title
            configuration.cornerStyle = .capsule
            button.configuration = configuration
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .primaryActionTriggered)
            buttons.append(button)
            navigation.addArrangedSubview(button)
        }
        select(3)
    }

    func select(_ index: Int) {
        loadViewIfNeeded()
        guard index >= 0, index < buttons.count else { return }
        let next: UIViewController
        if index < controllers.count {
            next = controllers[index]
        } else {
            let hosting = UIHostingController(rootView: SigningView(presentingViewController: self))
            next = UINavigationController(rootViewController: hosting)
            (next as? UINavigationController)?.navigationBar.prefersLargeTitles = true
        }
        guard next !== visibleController else { return }
        visibleController?.willMove(toParent: nil)
        visibleController?.view.removeFromSuperview()
        visibleController?.removeFromParent()
        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: content.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            next.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        next.didMove(toParent: self)
        visibleController = next
        for (buttonIndex, button) in buttons.enumerated() {
            button.configuration?.baseBackgroundColor = buttonIndex == index ? .systemBlue : .secondarySystemGroupedBackground
            button.configuration?.baseForegroundColor = buttonIndex == index ? .white : .secondaryLabel
            button.accessibilityTraits = buttonIndex == index ? [.button, .selected] : .button
        }
    }
}
#endif
