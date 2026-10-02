//
//  ReStoreWidgetBundle.swift
//  ReStoreWidgetExtension
//
//  Created by Riley Testut on 8/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

@main
struct ReStoreWidgetBundle: WidgetBundle
{
    var body: some Widget {
        AppDetailWidget()
        
        IconLockScreenWidget()
        TextLockScreenWidget()
        
        ActiveAppsWidget()
    }
}
