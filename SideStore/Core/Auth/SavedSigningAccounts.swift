import Foundation
import CoreData
import SideSign

struct SavedSigningAccount: Codable, Identifiable, Sendable {
    let id: String
    let appleID: String
    let password: String?
    let adsid: String
    let xcodeToken: String
    let teamIdentifier: String
    let teamName: String
    let teamType: Int
    let certificateSerialNumber: String?

    var team: ALTTeam {
        ALTTeam(identifier: teamIdentifier, name: teamName,
                type: ALTTeamType(rawValue: teamType) ?? .unknown)
    }

    var certificate: ALTCertificate? {
        certificateSerialNumber.flatMap { CertificateManager.shared.getSignableCertificate(for: $0) }
    }
}

struct AppSigningAssignment: Codable, Sendable {
    let accountID: String?
    let profileID: UUID?
}

struct OperationSigningIdentity: Sendable {
    let account: SavedSigningAccount?
    let team: ALTTeam
    let certificate: ALTCertificate?
    let profile: ALTProvisioningProfile?

    @TaskLocal static var current: OperationSigningIdentity?
}

actor SavedSigningAccounts {
    static let shared = SavedSigningAccounts()
    private let assignmentsKey = "restore.appSigningAssignments"
    private let defaultAccountKey = "restore.defaultSigningAccount"
    private let defaultProfileKey = "restore.defaultSigningProfile"

    func accounts() throws -> [SavedSigningAccount] {
        guard let data = try Keychain.shared.savedSigningAccountsData() else { return [] }
        return try JSONDecoder().decode([SavedSigningAccount].self, from: data)
    }

    func save(_ account: SavedSigningAccount) throws {
        var saved = try accounts().filter { $0.id != account.id }
        saved.append(account)
        try Keychain.shared.setSavedSigningAccountsData(JSONEncoder().encode(saved))
    }

    @discardableResult
    func captureCurrentAccount(team suppliedTeam: ALTTeam? = nil,
                               certificate suppliedCertificate: ALTCertificate? = nil) async throws -> SavedSigningAccount? {
        guard let appleID = Keychain.shared.appleIDEmailAddress,
              let adsid = Keychain.shared.appleIDAdsid,
              let token = Keychain.shared.appleIDXcodeToken else { return nil }
        let password = Keychain.shared.appleIDPassword
        let state: (String, ALTTeam)? = try await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            guard let team = DatabaseManager.shared.activeTeam(in: context),
                  let account = DatabaseManager.shared.activeAccount(in: context),
                  account.appleID.caseInsensitiveCompare(appleID) == .orderedSame else { return nil }
            return (account.identifier, suppliedTeam ?? ALTTeam(identifier: team.identifier, name: team.name, type: team.type))
        }
        guard let (accountID, team) = state else { return nil }
        let existing = try accounts().first { $0.id == accountID }
        let certificate = suppliedCertificate ?? existing?.certificate ?? CertificateManager.shared.activeCertificate?.certificate
        if let certificate { try CertificateManager.shared.storeCertificate(certificate) }
        let account = SavedSigningAccount(id: accountID, appleID: appleID, password: password,
                                         adsid: adsid, xcodeToken: token,
                                         teamIdentifier: team.identifier, teamName: team.name, teamType: team.type.rawValue,
                                         certificateSerialNumber: certificate?.serialNumber)
        try save(account)
        let legacyApps: [String] = try await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            try context.fetch(InstalledApp.fetchRequest()).filter {
                $0.team?.account?.identifier == accountID
            }.map { $0.bundleIdentifier }
        }
        let identity = OperationSigningIdentity(account: account, team: team, certificate: certificate, profile: nil)
        for bundleID in legacyApps where ProfileManager.shared.getAssignedProfile(for: bundleID) == nil {
            if try assignment(for: bundleID) == nil { try remember(identity, for: bundleID) }
        }
        return account
    }

    func selectAccount(_ id: String) throws {
        guard try accounts().contains(where: { $0.id == id }) else {
            throw OperationError.invalidParameters("This saved account is unavailable. Sign in again in Signing.")
        }
        UserDefaults.standard.set(id, forKey: defaultAccountKey)
        UserDefaults.standard.removeObject(forKey: defaultProfileKey)
    }

    func remove(_ id: String) async throws {
        let saved = try accounts()
        guard let account = saved.first(where: { $0.id == id }) else { return }
        guard !AppManager.shared.isActivelyManagingAnyApp else {
            throw OperationError.invalidParameters("Wait for app operations to finish before removing an account.")
        }
        try Keychain.shared.setSavedSigningAccountsData(JSONEncoder().encode(saved.filter { $0.id != id }))
        if selectedAccountID() == id { UserDefaults.standard.removeObject(forKey: defaultAccountKey) }
        if Keychain.shared.appleIDEmailAddress == account.appleID {
            await AuthManager.shared.signOut(keepCertificate: true)
        }
        // Keep app assignments: they must request this account again instead of switching owners.
    }

    func selectProfile(_ profile: ALTProvisioningProfile) throws {
        guard let certificate = ProfileManager.shared.getMatchingCertificate(for: profile) else {
            throw OperationError.invalidParameters("Import the certificate and matching private key for this provisioning profile first.")
        }
        try ImportedSigningValidation.validate(profile, certificate: certificate)
        UserDefaults.standard.set(profile.uuid.uuidString, forKey: defaultProfileKey)
        UserDefaults.standard.removeObject(forKey: defaultAccountKey)
    }

    func selectedAccountID() -> String? { UserDefaults.standard.string(forKey: defaultAccountKey) }
    func selectedProfileID() -> String? { UserDefaults.standard.string(forKey: defaultProfileKey) }

    func restoreActiveAccount(_ account: SavedSigningAccount) async throws {
        try await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            var restoredAccount: Account?
            for saved in try context.fetch(Account.fetchRequest()) {
                saved.isActiveAccount = saved.identifier == account.id
                if saved.isActiveAccount { restoredAccount = saved }
            }
            for team in try context.fetch(Team.fetchRequest()) {
                team.isActiveTeam = team.identifier == account.teamIdentifier
                if team.isActiveTeam { team.account = restoredAccount }
            }
            try context.save()
        }
    }

    func forgetAccount(appleID: String) throws {
        let saved = try accounts()
        let removed = saved.filter { $0.appleID == appleID }.map { $0.id }
        try Keychain.shared.setSavedSigningAccountsData(JSONEncoder().encode(saved.filter { $0.appleID != appleID }))
        if let selected = selectedAccountID(), removed.contains(selected) {
            UserDefaults.standard.removeObject(forKey: defaultAccountKey)
        }
    }

    func assignment(for bundleIdentifier: String) throws -> AppSigningAssignment? {
        guard let data = UserDefaults.standard.data(forKey: assignmentsKey) else { return nil }
        return try JSONDecoder().decode([String: AppSigningAssignment].self, from: data)[bundleIdentifier]
    }

    func remember(_ identity: OperationSigningIdentity, for bundleIdentifier: String) throws {
        var assignments: [String: AppSigningAssignment] = [:]
        if let data = UserDefaults.standard.data(forKey: assignmentsKey) {
            assignments = try JSONDecoder().decode([String: AppSigningAssignment].self, from: data)
        }
        assignments[bundleIdentifier] = AppSigningAssignment(accountID: identity.account?.id, profileID: identity.profile?.uuid)
        UserDefaults.standard.set(try JSONEncoder().encode(assignments), forKey: assignmentsKey)
    }

    func forgetAssignment(for bundleIdentifier: String) throws {
        guard let data = UserDefaults.standard.data(forKey: assignmentsKey) else { return }
        var assignments = try JSONDecoder().decode([String: AppSigningAssignment].self, from: data)
        assignments.removeValue(forKey: bundleIdentifier)
        UserDefaults.standard.set(try JSONEncoder().encode(assignments), forKey: assignmentsKey)
    }

    func identity(for operation: AppOperation, in context: NSManagedObjectContext) async throws -> OperationSigningIdentity? {
        switch operation {
        case .deleteApp, .removeApp, .removeDeactivatedApp:
            return nil
        default:
            break
        }
        let stored = try assignment(for: operation.bundleIdentifier)
        let installedIdentity: (accountID: String?, certificateID: String?, teamID: String?)? = await context.perform {
            guard let app = operation.app as? InstalledApp,
                  let object = try? context.existingObject(with: app.objectID),
                  let installed = object as? InstalledApp else { return nil }
            return (installed.team?.account?.identifier, installed.certificateSerialNumber,
                    ALTApplication(fileURL: installed.fileURL)?.provisioningProfile?.teamIdentifier)
        }
        let isExistingApp = operation.app is InstalledApp
        let legacyProfileID = ProfileManager.shared.getAssignedProfile(for: operation.bundleIdentifier)?.uuid.uuidString
        let profileID = legacyProfileID ?? stored?.profileID?.uuidString ?? (isExistingApp ? nil : selectedProfileID())
        if let profileID {
            guard let uuid = UUID(uuidString: profileID), let profile = ProfileManager.shared.getProfile(uuid: uuid),
                  let certificate = ProfileManager.shared.getMatchingCertificate(for: profile) else {
                throw OperationError.invalidParameters("The saved signing profile or its private key is missing. Restore it in Signing.")
            }
            try ImportedSigningValidation.validate(profile, certificate: certificate)
            let team = ALTTeam(identifier: profile.teamIdentifier, name: profile.teamName,
                               type: profile.isFreeProvisioningProfile ? .free : .individual)
            return OperationSigningIdentity(account: nil, team: team, certificate: certificate, profile: profile)
        }
        let saved = try accounts()
        let legacyAccount = saved.first { account in
            if let certificateID = installedIdentity?.certificateID {
                return account.certificateSerialNumber == certificateID
            }
            return installedIdentity?.teamID == account.teamIdentifier
        }
        var accountID = stored?.accountID ?? installedIdentity?.accountID ?? legacyAccount?.id
        if !isExistingApp { accountID = accountID ?? selectedAccountID() }
        // The first explicit host resign during onboarding establishes its signing account.
        if case .resign = operation, operation.bundleIdentifier.isAltStoreAppID,
           stored == nil, installedIdentity?.accountID == nil, accountID == nil {
            accountID = saved.first { $0.appleID == Keychain.shared.appleIDEmailAddress }?.id
        }
        let account: SavedSigningAccount?
        if let accountID {
            account = saved.first { $0.id == accountID }
            guard account != nil else {
                throw OperationError.invalidParameters("The account that signed this app is unavailable. Sign into that account again in Signing.")
            }
        } else if !isExistingApp {
            account = saved.first { $0.appleID == Keychain.shared.appleIDEmailAddress }
        } else {
            throw OperationError.invalidParameters("This app's original signing account could not be identified. Sign into that account again or assign its imported profile in Signing.")
        }
        guard let account else {
            throw OperationError.invalidParameters("Choose an Apple account or import a certificate, private key, and provisioning profile in Signing.")
        }
        guard let certificate = account.certificate else {
            throw OperationError.invalidParameters("This account's signing certificate is missing. Sign into it again in Signing.")
        }
        return OperationSigningIdentity(account: account, team: account.team, certificate: certificate, profile: nil)
    }
}
