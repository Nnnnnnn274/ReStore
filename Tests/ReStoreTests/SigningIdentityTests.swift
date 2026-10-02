import XCTest
import SideSign
@testable import SideStore

final class SigningIdentityTests: XCTestCase {
    func testWildcardSignedIdentifiersBecomeConcreteAndKeepTheProfilePrefix() throws {
        XCTAssertEqual(try ImportedAppSigner.applicationIdentifier(profileIdentifier: "LegacyPrefix.com.example.*",
                                                                  bundleIdentifier: "com.example.app.widget"),
                       "LegacyPrefix.com.example.app.widget")
        XCTAssertThrowsError(try ImportedAppSigner.applicationIdentifier(profileIdentifier: "Invalid",
                                                                       bundleIdentifier: "com.example.app"))
        XCTAssertThrowsError(try ImportedAppSigner.applicationIdentifier(profileIdentifier: "Team.*",
                                                                       bundleIdentifier: "com.example.*"))
    }

    private func identity(_ id: String) -> OperationSigningIdentity {
        let account = SavedSigningAccount(id: id, appleID: "\(id)@example.invalid", password: nil,
                                         adsid: "dsid-\(id)", xcodeToken: "test-token-\(id)",
                                         teamIdentifier: "team-\(id)", teamName: id,
                                         teamType: ALTTeamType.free.rawValue, certificateSerialNumber: nil)
        return OperationSigningIdentity(account: account, team: account.team, certificate: nil, profile: nil)
    }

    func testConcurrentAccountsKeepTheirTokensAcrossSuspensionAndChildTasks() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ["A", "B"] {
                let signingIdentity = identity(id)
                group.addTask {
                    try await OperationSigningIdentity.$current.withValue(signingIdentity) {
                        await Task.yield()
                        XCTAssertEqual(AuthManager.shared.adsid, "dsid-\(id)")
                        XCTAssertEqual(AuthManager.shared.xcodeToken, "test-token-\(id)")
                        XCTAssertNil(AuthManager.shared.password)
                        let team = try await AuthManager.shared.getAuthenticatedTeam()
                        XCTAssertEqual(team.identifier, "team-\(id)")
                        let childAccount = await Task { OperationSigningIdentity.current?.account?.id }.value
                        XCTAssertEqual(childAccount, id)
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertNil(OperationSigningIdentity.current)
    }

    func testImportedSigningNeverExposesGlobalAppleCredentialsOrContactsPortal() async {
        let imported = OperationSigningIdentity(account: nil,
                                                team: ALTTeam(identifier: "imported", name: "Imported", type: .individual),
                                                certificate: nil, profile: nil)
        await OperationSigningIdentity.$current.withValue(imported) {
            XCTAssertFalse(AuthManager.shared.isAuthenticated)
            XCTAssertNil(AuthManager.shared.currentAppleID)
            XCTAssertNil(AuthManager.shared.password)
            XCTAssertNil(AuthManager.shared.adsid)
            XCTAssertNil(AuthManager.shared.xcodeToken)
            do {
                _ = try await AuthManager.shared.getAuthenticatedSession()
                XCTFail("Imported signing must reject developer portal authentication.")
            } catch {
                XCTAssertTrue(error is OperationError)
            }
        }
    }

    func testProfilesAuthorizeMainAppAndExtensionsWithoutAcceptingOtherPrefixes() {
        func profile(_ pattern: String) -> ALTProvisioningProfile {
            ALTProvisioningProfile(name: "Test", uuid: UUID(), bundleIdentifier: pattern,
                                   teamIdentifier: "TestTeam", teamName: "Test",
                                   creationDate: .distantPast, expirationDate: .distantFuture, data: Data())
        }
        let wildcard = profile("com.example.*")
        XCTAssertTrue(ImportedSigningValidation.permits(wildcard, bundleIdentifier: "com.example.app"))
        XCTAssertTrue(ImportedSigningValidation.permits(wildcard, bundleIdentifier: "com.example.app.widget"))
        XCTAssertFalse(ImportedSigningValidation.permits(wildcard, bundleIdentifier: "com.exampleOther.app"))
        XCTAssertFalse(ImportedSigningValidation.permits(wildcard, bundleIdentifier: "com.example.*"))
        XCTAssertFalse(ImportedSigningValidation.permits(profile("*"), bundleIdentifier: ""))
        XCTAssertTrue(ImportedSigningValidation.permits(profile("*"), bundleIdentifier: "com.other.app"))
        let explicit = profile("com.example.app")
        XCTAssertTrue(ImportedSigningValidation.permits(explicit, bundleIdentifier: "com.example.app"))
        XCTAssertFalse(ImportedSigningValidation.permits(explicit, bundleIdentifier: "com.example.app.widget"))
    }
}
