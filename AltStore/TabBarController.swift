//
//  TabBarController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import SwiftUI

extension TabBarController
{
    private enum Tab: Int, CaseIterable
    {
        case news
        case sources
        case browse
        case myApps
        case settings
    }
}

final class TabBarController: UITabBarController
{
    private var initialSegue: (identifier: String, sender: Any?)?
    
    private var _viewDidAppear = false
    
    private var sourcesViewController: SourcesViewController!
    #if os(iOS)
    private var workspace: SideStoreWorkspaceViewController?
    private let sectionDock = UIStackView()
    private let sectionToggle = UIButton(type: .system)
    private var sectionButtons: [UIButton] = []
    private var dockBottom: NSLayoutConstraint?
    #endif
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.presentSources(_:)), name: AppDelegate.addSourceDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
    }
    
    override func viewDidLoad() 
    {
        super.viewDidLoad()
        debugLog("[TabBarController] viewDidLoad()")
        
        let browseNavigationController = self.viewControllers![Tab.browse.rawValue] as! UINavigationController
        browseNavigationController.tabBarItem.image = UIImage(systemName: "bag")
        
        let sourcesNavigationController = self.viewControllers![Tab.sources.rawValue] as! UINavigationController
        self.sourcesViewController = sourcesNavigationController.viewControllers.first as? SourcesViewController
        #if os(iOS)
        let workspace = SideStoreWorkspaceViewController(controllers: self.viewControllers ?? [])
        self.workspace = workspace
        let liveContainer = UIHostingController(rootView: NavigationView { LiveContainerView() })
        self.setViewControllers([liveContainer, workspace], animated: false)
        self.selectedIndex = UserDefaults.standard.integer(forKey: "restore.selectedSection") == 0 ? 1 : 0
        configureSectionDock()
        #endif
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        debugLog("[TabBarController] viewDidAppear() — TabBarController is now visible")
        
        _viewDidAppear = true
        
        if let (identifier, sender) = self.initialSegue
        {
            self.initialSegue = nil
            self.performSegue(withIdentifier: identifier, sender: sender)
        }
    }

    #if os(iOS)
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tabBar.isHidden = true
        dockBottom?.constant = -(view.window?.safeAreaInsets.bottom ?? 0) - 8
        view.bringSubviewToFront(sectionDock)
    }
    #endif
    
    override func performSegue(withIdentifier identifier: String, sender: Any?)
    {
        guard _viewDidAppear else {
            self.initialSegue = (identifier, sender)
            return
        }
        
        super.performSegue(withIdentifier: identifier, sender: sender)
    }
}

#if os(iOS)
private extension TabBarController {
    func configureSectionDock() {
        tabBar.isHidden = true
        view.tintColor = .systemBlue
        view.backgroundColor = .systemGroupedBackground
        sectionDock.axis = .vertical
        sectionDock.spacing = 6
        sectionDock.translatesAutoresizingMaskIntoConstraints = false
        sectionToggle.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        sectionToggle.addAction(UIAction { [weak self] _ in
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "restore.hideSections"), forKey: "restore.hideSections")
            self?.updateSectionDock()
        }, for: .primaryActionTriggered)
        sectionDock.addArrangedSubview(sectionToggle)
        let row = UIStackView()
        row.spacing = 12
        row.distribution = .fillEqually
        for (index, title) in ["LiveContainer", "SideStore"].enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            configuration.image = UIImage(systemName: index == 0 ? "square.grid.2x2.fill" : "bag.fill")
            configuration.imagePadding = 8
            configuration.cornerStyle = .large
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 12, bottom: 18, trailing: 12)
            button.configuration = configuration
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.addAction(UIAction { [weak self] _ in self?.selectSection(index) }, for: .primaryActionTriggered)
            row.addArrangedSubview(button)
            sectionButtons.append(button)
        }
        sectionDock.addArrangedSubview(row)
        view.addSubview(sectionDock)
        let bottom = sectionDock.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        dockBottom = bottom
        NSLayoutConstraint.activate([
            sectionDock.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sectionDock.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottom
        ])
        updateSectionDock()
    }

    func selectSection(_ index: Int) {
        selectedIndex = index
        UserDefaults.standard.set(index == 0 ? 1 : 0, forKey: "restore.selectedSection")
        updateSectionDock()
    }

    func updateSectionDock() {
        let hidden = UserDefaults.standard.bool(forKey: "restore.hideSections")
        sectionDock.arrangedSubviews.last?.isHidden = hidden
        sectionToggle.setTitle(hidden ? "Show sections  ⌃" : "Hide sections  ⌄", for: .normal)
        sectionToggle.accessibilityLabel = hidden ? "Show LiveContainer and SideStore tabs" : "Hide LiveContainer and SideStore tabs"
        additionalSafeAreaInsets.bottom = hidden ? 30 : 96
        for (index, button) in sectionButtons.enumerated() {
            button.configuration?.baseBackgroundColor = index == selectedIndex ? .systemBlue : .secondarySystemGroupedBackground
            button.configuration?.baseForegroundColor = index == selectedIndex ? .white : .label
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
        }
    }
}

#endif

extension TabBarController
{
    @objc func presentSources(_ sender: Any)
    {
        if let presentedViewController = self.presentedViewController
        {
            presentedViewController.dismiss(animated: true) {
                self.presentSources(sender)
            }
            
            return
        }
                
        if let notification = (sender as? Notification), let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
        {
            self.sourcesViewController?.deepLinkSourceURL = sourceURL
        }
        
        #if os(iOS)
        self.selectSection(1)
        self.workspace?.select(Tab.sources.rawValue)
        #else
        self.selectedIndex = Tab.sources.rawValue
        #endif
    }
}

private extension TabBarController
{
    @objc func importApp(_ notification: Notification)
    {
        #if os(iOS)
        self.selectSection(1)
        self.workspace?.select(Tab.myApps.rawValue)
        #else
        self.selectedIndex = Tab.myApps.rawValue
        #endif
    }

    @objc func openErrorLog(_ notification: Notification)
    {
        #if os(iOS)
        self.selectSection(1)
        self.workspace?.select(Tab.settings.rawValue)
        #else
        self.selectedIndex = Tab.settings.rawValue
        #endif
    }
}
