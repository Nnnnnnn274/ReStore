#if os(iOS)
import Foundation
import UIKit
import Security
import SideSign

struct ContainerApp: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let version: String
    let containerID: String
    let icon: UIImage?
}

@MainActor
final class BuiltInLiveContainer: ObservableObject {
    @Published private(set) var apps: [ContainerApp] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private let manager = FileManager.default
    private var documents: URL { manager.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var applications: URL { documents.appendingPathComponent("Applications", isDirectory: true) }
    private var containers: URL { documents.appendingPathComponent("Data/Application", isDirectory: true) }

    func reload() {
        do {
            var runtimeError: NSError?
            guard RSLCInitialize(&runtimeError) else { throw runtimeError ?? OperationError.unknownResult as NSError }
            try manager.createDirectory(at: applications, withIntermediateDirectories: true)
            try manager.createDirectory(at: containers, withIntermediateDirectories: true)
            apps = try manager.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .compactMap { url in
                    let metadata = RSLCAppMetadata(url.path, nil) as? [String: Any]
                    let infoURL = url.appendingPathComponent("LCAppInfo.plist")
                    guard let metadata, let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
                          let container = info["LCDataUUID"] as? String,
                          UUID(uuidString: container) != nil else { return nil }
                    let name = (metadata["name"] as? String) ?? url.lastPathComponent
                    let bundleIdentifier = (metadata["bundleIdentifier"] as? String) ?? ""
                    let version = (metadata["version"] as? String) ?? ""
                    return ContainerApp(id: url.lastPathComponent, name: name,
                                        bundleIdentifier: bundleIdentifier,
                                        version: version, containerID: container,
                                        icon: metadata["icon"] as? UIImage)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let startupError = UserDefaults.standard.string(forKey: "error") {
                errorMessage = startupError
                UserDefaults.standard.removeObject(forKey: "error")
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func importApp(from source: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let temporary = manager.uniqueTemporaryURL()
        var destination: URL?
        var containerURL: URL?
        do {
            var runtimeError: NSError?
            guard RSLCInitialize(&runtimeError) else { throw runtimeError ?? OperationError.unknownResult as NSError }
            try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let archive = temporary.appendingPathComponent("Import.ipa")
            try manager.copyItem(at: source, to: archive)
            let extracted = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.unzipAppBundle(at: archive, to: temporary.appendingPathComponent("Extracted"))
            }.value
            let appID = UUID().uuidString
            let dataID = UUID().uuidString
            let target = applications.appendingPathComponent(appID + ".app", isDirectory: true)
            let dataDirectory = containers.appendingPathComponent(dataID, isDirectory: true)
            destination = target; containerURL = dataDirectory
            try manager.createDirectory(at: applications, withIntermediateDirectories: true)
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try manager.moveItem(at: extracted, to: target)
            guard let app = ALTApplication(fileURL: target) else { throw OperationError.invalidApp(reason: "This IPA has no readable app bundle.") }
            let usedGroups = try manager.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil).compactMap { url in
                (NSDictionary(contentsOf: url.appendingPathComponent("LCContainerInfo.plist")) as? [String: Any])?["keychainGroupId"] as? Int
            }
            guard let group = (1...127).first(where: { !usedGroups.contains($0) }) else {
                throw OperationError.invalidParameters("All available container keychain groups are in use.")
            }
            let info: [String: Any] = ["name": "Default", "appIdentifier": app.bundleIdentifier,
                                       "keychainGroupId": group, "isolateAppGroup": true,
                                       "spoofIdentifierForVendor": true, "spoofedIdentifierForVendor": UUID().uuidString]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            try data.write(to: dataDirectory.appendingPathComponent("LCContainerInfo.plist"), options: .atomic)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                RSLCPrepareApp(target.path, dataID) { success, message in
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: OperationError.invalidApp(reason: message ?? "LiveContainer could not prepare this app.")) }
                }
            }
            reload()
        } catch {
            if let destination { try? manager.removeItem(at: destination) }
            if let containerURL { try? manager.removeItem(at: containerURL) }
            errorMessage = error.localizedDescription
        }
        try? manager.removeItem(at: temporary)
    }

    func open(_ app: ContainerApp) {
        guard !isBusy else { return }
        guard !AppManager.shared.isActivelyManagingAnyApp else {
            errorMessage = "Wait for SideStore's app operations to finish before opening a container app."
            return
        }
        var error: NSError?
        if !RSLCOpenApp(app.id, app.containerID, &error) { errorMessage = error?.localizedDescription }
    }

    func delete(_ app: ContainerApp) {
        guard !isBusy else { return }
        do {
            let appURL = applications.appendingPathComponent(app.id).standardizedFileURL
            let dataURL = containers.appendingPathComponent(app.containerID).standardizedFileURL
            guard appURL.deletingLastPathComponent() == applications.standardizedFileURL,
                  dataURL.deletingLastPathComponent() == containers.standardizedFileURL,
                  UUID(uuidString: app.containerID) != nil else {
                throw OperationError.invalidParameters("Invalid container path.")
            }
            // Match the alias used by LiveContainer's guest keychain hooks.
            for itemClass in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity] {
                let status = SecItemDelete([kSecClass as String: itemClass, "alis": app.containerID] as CFDictionary)
                if status != errSecSuccess && status != errSecItemNotFound {
                    debugLog("[LiveContainer] Could not remove container keychain items: \(status)")
                }
            }
            try manager.removeItem(at: appURL)
            if manager.fileExists(atPath: dataURL.path) { try manager.removeItem(at: dataURL) }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
