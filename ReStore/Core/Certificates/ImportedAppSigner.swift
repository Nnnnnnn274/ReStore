import Foundation
import SideSign
import CodeSignKit

enum ImportedAppSigner {
    static func applicationIdentifier(profileIdentifier: String, bundleIdentifier: String) throws -> String {
        guard let separator = profileIdentifier.firstIndex(of: "."),
              !bundleIdentifier.isEmpty, !bundleIdentifier.contains("*") else {
            throw OperationError.invalidParameters("The profile contains an invalid application identifier.")
        }
        return String(profileIdentifier[...separator]) + bundleIdentifier
    }

    static func sign(at url: URL, certificate: ALTCertificate,
                     profiles: [ALTProvisioningProfile]) throws {
        guard let main = ALTApplication(fileURL: url) else {
            throw OperationError.invalidApp(reason: "The imported signing app bundle is unreadable.")
        }
        var entitlementsByPath: [String: String] = [:]
        for app in [main] + Array(main.appExtensions) {
            guard let profile = profiles.first(where: { $0.bundleIdentifier == app.bundleIdentifier }),
                  let authorizedIdentifier = profile.entitlements["application-identifier"] as? String else {
                throw OperationError.missingProvisioningProfile(reason: "No imported profile authorizes '\(app.bundleIdentifier)'.")
            }
            var entitlements = profile.entitlements
            let original = app.entitlements
            for key in Array(entitlements.keys) where key != "application-identifier" &&
                key != "com.apple.developer.team-identifier" && key != "get-task-allow" {
                if original[key] == nil { entitlements.removeValue(forKey: key) }
            }
            let identifier = try applicationIdentifier(profileIdentifier: authorizedIdentifier,
                                                       bundleIdentifier: app.bundleIdentifier)
            entitlements["application-identifier"] = identifier
            if let groups = original["keychain-access-groups"] as? [String],
               let allowed = profile.entitlements["keychain-access-groups"] as? [String],
               let separator = identifier.firstIndex(of: ".") {
                let prefix = String(identifier[...separator])
                var resolvedGroups = try groups.map { group in
                    guard let separator = group.firstIndex(of: ".") else {
                        throw OperationError.invalidParameters("A keychain access group is missing its signing prefix.")
                    }
                    let suffix = String(group[group.index(after: separator)...])
                    let resolved = prefix + (suffix == "*" ? app.bundleIdentifier : suffix)
                    guard allowed.contains(where: { pattern in
                        pattern == resolved || (pattern.hasSuffix("*") && resolved.hasPrefix(String(pattern.dropLast())))
                    }) else {
                        throw OperationError.invalidParameters("The provisioning profile does not authorize keychain group '\(resolved)'.")
                    }
                    return resolved
                }
                if app.isAltStoreApp {
                    guard allowed.contains(where: { $0 == identifier || ($0.hasSuffix("*") && identifier.hasPrefix(String($0.dropLast()))) }) else {
                        throw OperationError.invalidParameters("The profile does not authorize ReStore's own keychain access group.")
                    }
                    resolvedGroups.removeAll { $0 == identifier }
                    resolvedGroups.insert(identifier, at: 0)
                }
                entitlements["keychain-access-groups"] = resolvedGroups
            }
            let data = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
            guard let xml = String(data: data, encoding: .utf8) else { throw OperationError.unknownResult }
            entitlementsByPath[app.fileURL.resolvingSymlinksInPath().path] = xml
            if let executable = app.executableURL {
                entitlementsByPath[executable.resolvingSymlinksInPath().path] = xml
            }
            try profile.data.write(to: app.fileURL.appendingPathComponent("embedded.mobileprovision"), options: .atomic)
        }
        let rootPath = main.fileURL.resolvingSymlinksInPath().path
        let preparedEntitlements = entitlementsByPath
        try CodeSigner.sign(appPath: main.fileURL.path, keyData: certificate.unencryptedP12Data(),
                            entitlementProvider: { path in
            let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty { return preparedEntitlements[rootPath] ?? "" }
            let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : main.fileURL.appendingPathComponent(path)
            return preparedEntitlements[candidate.resolvingSymlinksInPath().path] ?? ""
        }, progress: {})
    }
}
