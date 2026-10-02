//
//  UpdateAppCertificateOperation.swift
//  ReStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import SideSign

final class UpdateAppCertificateOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[UpdateAppCertificateOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[UpdateAppCertificateOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)

        if OperationSigningIdentity.current?.account != nil {
            // Account certificate renewal must apply to its own apps, never another account's key.
            self.setProgress(100)
            return
        }
        
        let targetBundleID = self.context.installedApp?.bundleIdentifier ?? self.context.targetBundleIdentifier
        let profileToUse = self.context.overrideProvisioningProfile ?? ProfileManager.shared.getAssignedProfile(for: targetBundleID)

        if let assignedProfile = profileToUse {
            guard let matchingCert = ProfileManager.shared.getMatchingCertificate(for: assignedProfile) else {
                throw OperationError.invalidParameters("The assigned profile's certificate and private key are missing. Restore them in Signing.")
            }
            try ImportedSigningValidation.validate(assignedProfile, certificate: matchingCert)
            debugLog("[UpdateAppCertificateOperation] Target bundle '\(targetBundleID)' using assigned profile: '\(assignedProfile.name)' (\(assignedProfile.uuid))")
            self.context.overrideProvisioningProfile = assignedProfile

            self.context.overrideSigningCertificate = matchingCert
        } else if let installedApp = self.context.installedApp, let serialNumber = installedApp.certificateSerialNumber {
            debugLog("[UpdateAppCertificateOperation] InstalledApp '\(installedApp.name)' has custom certificate serial: '\(serialNumber)'")
            if let customCert = CertificateManager.shared.getSignableCertificate(for: serialNumber) {
                debugLog("[UpdateAppCertificateOperation] Loaded custom certificate '\(customCert.serialNumber)' for app '\(installedApp.name)'. Setting context.overrideSigningCertificate.")
                self.context.overrideSigningCertificate = customCert
            } else {
                throw OperationError.invalidParameters("The certificate and private key that signed '\(installedApp.name)' are missing. Restore them in Signing.")
            }
        }
        
        self.setProgress(100)
    }
}
