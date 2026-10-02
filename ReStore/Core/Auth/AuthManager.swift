//
//  AuthManager.swift
//  ReStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign
import CoreData

public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()
    
    private var portalProxy: DeveloperPortalProxyWithAuth {
        DeveloperPortalProxy.shared as! DeveloperPortalProxyWithAuth
    }
    
    private init() {}
    
    private var team: ALTTeam?
    private var session: ALTAppleAPISession?

    public var isAuthenticated: Bool {
        if let identity = OperationSigningIdentity.current { return identity.account != nil }
        let hasEmail = Keychain.shared.appleIDEmailAddress != nil
        let hasPassword = Keychain.shared.appleIDPassword != nil
        let hasToken = Keychain.shared.appleIDXcodeToken != nil
        return hasEmail && (hasPassword || hasToken)
    }
    
    public var currentAppleID: String? {
        get {
            if let identity = OperationSigningIdentity.current { return identity.account?.appleID }
            return Keychain.shared.appleIDEmailAddress
        }
        set { Keychain.shared.appleIDEmailAddress = newValue }
    }
    
    public var password: String? {
        get {
            if let identity = OperationSigningIdentity.current { return identity.account?.password }
            return Keychain.shared.appleIDPassword
        }
        set { Keychain.shared.appleIDPassword = newValue }
    }
    
    public var adsid: String? {
        get {
            if let identity = OperationSigningIdentity.current { return identity.account?.adsid }
            return Keychain.shared.appleIDAdsid
        }
        set { Keychain.shared.appleIDAdsid = newValue }
    }
    
    public var xcodeToken: String? {
        get {
            if let identity = OperationSigningIdentity.current { return identity.account?.xcodeToken }
            return Keychain.shared.appleIDXcodeToken
        }
        set { Keychain.shared.appleIDXcodeToken = newValue }
    }
    
    public var hasStoredPassword: Bool {
        return password != nil
    }
    
    public var hasStoredXcodeToken: Bool {
        return xcodeToken != nil
    }
    
    public func signOut(
        keepCertificate: Bool = false,
        keepAnisetteData: Bool = true,
        keepAnisetteHeaders: Bool = true,
        keepSideSignHeaders: Bool = true,
        forgetSavedAccount: Bool = true
    ) async {
        if forgetSavedAccount, let appleID = Keychain.shared.appleIDEmailAddress {
            do { try await SavedSigningAccounts.shared.forgetAccount(appleID: appleID) }
            catch { debugLog("[AuthManager] Could not remove saved account credentials: \(error)") }
        }
        self.session = nil
        self.team = nil
        if !keepCertificate {
            debugLog("[AuthManager] Clearing signing certificate in cert manager and keychain.")
            CertificateManager.shared.clearActiveCertificate()
            debugLog("[AuthManager] Cleared signing certificate in cert manager and keychain.")

        } else {
            debugLog("[AuthManager] Preserved signing certificate in cert manager and keychain.")
        }
        debugLog("[AuthManager] Clearing account and team info in database.")
        await DatabaseManager.shared.deactivateActiveAccountAndTeam()
        debugLog("[AuthManager] Cleared account and team info in database.")

        debugLog("[AuthManager] Clearing sign-in info from keychain.")
        Keychain.shared.clearSignInInfo(keepAnisetteData: keepAnisetteData)
        debugLog("[AuthManager] Cleared sign-in info from keychain.")

        if !keepAnisetteHeaders {
            debugLog("[AuthManager] Resetting Anisette header customizations to defaults.")
            AnisetteConfigManager.shared.resetToDefaults()
        }

        if !keepSideSignHeaders {
            debugLog("[AuthManager] Resetting SideSign header customizations to defaults.")
            SideSignConfigManager.shared.resetToDefaults()
        }

        AnisetteDataManager.shared.clearCache()
    }
    
    @discardableResult
    public func getAuthenticatedSession() async throws -> ALTAppleAPISession {
        if let identity = OperationSigningIdentity.current, identity.account == nil {
            throw OperationError.invalidParameters("Imported signing must use local provisioning profiles instead of the Apple Developer Portal.")
        }
        let accountKey = OperationSigningIdentity.current?.account?.id ?? "active"
        return try await TaskChainCoalescer.shared.coalesce(key: "apple_auth_session_" + accountKey) {
            guard let adsid = self.adsid,                           // directory services id
                  let xcodeToken = self.xcodeToken else             // xcode token
            {
                debugLog("[AuthManager] No stored tokens found.")
                throw OperationError.notAuthenticated
            }
            let anisetteData = try await AnisetteProvider.fetch()   // one time pass
            let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()
            
            let session = ALTAppleAPISession(
                dsid: adsid,
                authToken: xcodeToken,
                anisetteData: anisetteData,
                xcodeVersion: xcodeVersion
            )
            self.session = session
            return session
        }
    }

    public func getAuthenticatedTeam() async throws -> ALTTeam {
        if let identity = OperationSigningIdentity.current { return identity.team }
        if let team = self.team {
            return team
        }
        
        let team = try await self.resolveActiveTeam()
        self.team = team
        return team
    }

    private func resolveActiveTeam() async throws -> ALTTeam {
        try await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            guard let dbTeam = DatabaseManager.shared.activeTeam(in: context) else {
                throw OperationError.notAuthenticated
            }
            return ALTTeam(identifier: dbTeam.identifier, name: dbTeam.name, type: dbTeam.type)
        }
    }
    
    @discardableResult
    @MainActor
    func signIn(
        presentingViewController: UIViewController? = nil,
        skipDeviceRegistration: Bool = false,
        skipCertificateProvisioning: Bool = false,
        skipResign: Bool = false,
        skipHowTos: Bool = false
    ) async throws -> SignInResult {
        guard !signInInProgress, !AppManager.shared.isActivelyManagingAnyApp else {
            throw OperationError.invalidParameters("Wait for the current app or sign-in operation to finish before adding an account.")
        }
        signInInProgress = true
        defer { signInInProgress = false }
        let previousAccount = try await SavedSigningAccounts.shared.captureCurrentAccount()
        let previousCertificate = CertificateManager.shared.activeCertificate?.certificate
        if let previousCertificate { try CertificateManager.shared.storeCertificate(previousCertificate) }
        let previousCredentials = (Keychain.shared.appleIDEmailAddress, Keychain.shared.appleIDPassword,
                                   Keychain.shared.appleIDAdsid, Keychain.shared.appleIDXcodeToken)
        let previousTeam = self.team
        let previousLimit = UserDefaults.standard.activeAppsLimit
        CertificateManager.shared.clearActiveCertificate()
        self.team = nil
        self.session = nil
        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let signInFlowHandler = SignInFlowHandler(presentingViewController: presentingViewController)
        let context = StandaloneOperationContext(
            steps: .signIn,
            dbBackgroundContext: dbBackgroundContext
        )
        
        do {
            let signInOperation = try SignInOperation(
                context: context,
                signInHandler: signInFlowHandler,
                anisetteServerHandler: signInFlowHandler,
                skipDeviceRegistration: skipDeviceRegistration,
                skipCertificateProvisioning: skipCertificateProvisioning,
                skipResign: skipResign,
                skipHowTos: skipHowTos
            )
            let result = try await signInOperation.execute()
            self.team = result.team
            self.session = result.session
            return result
        } catch {
            Keychain.shared.appleIDEmailAddress = previousCredentials.0
            Keychain.shared.appleIDPassword = previousCredentials.1
            Keychain.shared.appleIDAdsid = previousCredentials.2
            Keychain.shared.appleIDXcodeToken = previousCredentials.3
            UserDefaults.standard.activeAppsLimit = previousLimit
            if let previousAccount {
                do { try await SavedSigningAccounts.shared.restoreActiveAccount(previousAccount) }
                catch { debugLog("[AuthManager] Could not restore the previous active account: \(error)") }
                self.team = previousAccount.team
            } else {
                await DatabaseManager.shared.deactivateActiveAccountAndTeam()
                self.team = previousTeam
            }
            do { try CertificateManager.shared.setActiveCertificate(previousCertificate) }
            catch { debugLog("[AuthManager] Could not restore the previous active certificate: \(error)") }
            throw error
        }
    }

    @MainActor private var signInInProgress = false
    
    
    // Developer Portal Operations
    public func signIn(appleID: String, 
                       password: String, 
                       anisetteData: ALTAnisetteData, 
                       xcodeVersion: String, 
                       machinePassword: String? = nil,
                       accountRepairHandler: DeveloperPortal.AccountRepairHandler = DeveloperPortal.defaultAccountRepairHandler,
                       verificationHandler: DeveloperPortal.VerificationHandler?) async throws -> (ALTAccount, ALTAppleAPISession) 
    {
        return try await self.portalProxy.signIn(
            appleID: appleID, 
            password: password, 
            anisetteData: anisetteData, 
            xcodeVersion: xcodeVersion, 
            machinePassword: machinePassword,
            accountRepairHandler: accountRepairHandler, 
            verificationHandler: verificationHandler
        )
    }
}

fileprivate extension DatabaseManager {
    //TODO: this is not clean, but for now this should be fine, ie we should later make this proper async instead of blocking
    func deactivateActiveAccountAndTeam() async {
        guard self.isStarted else {
            debugLog("[AuthManager] DatabaseManager is not started. Skipping CoreData active account/team deactivation.")
            return
        }
        let bgContext = self.persistentContainer.newBackgroundContext()
        await bgContext.perform {
            if let account = self.activeAccount(in: bgContext) {
                account.isActiveAccount = false
            }
            if let team = self.activeTeam(in: bgContext) {
                team.isActiveTeam = false
            }
            do {
                try bgContext.save()
            } catch {
                debugLog("[AuthManager] Failed to save CoreData context when deactivating active account and team: \(error)")
            }
        }
        
        await self.viewContext.perform {
            self.viewContext.processPendingChanges()
            self.viewContext.refreshAllObjects()
        }
    }
}
