#if os(iOS)
import SwiftUI
import SideSign
import UniformTypeIdentifiers

struct SigningView: View {
    weak var presentingViewController: UIViewController?
    @State private var accounts: [SavedSigningAccount] = []
    @State private var profiles: [ALTProvisioningProfile] = []
    @State private var accountID: String?
    @State private var profileID: String?
    @State private var importing = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("Every app remembers its signing identity", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text("New installs use your selection below. Refresh automatically uses the account or imported profile saved for each app.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Section(header: Text("Apple accounts")) {
                ForEach(accounts) { account in
                    SwiftUI.Button {
                        run {
                            try await SavedSigningAccounts.shared.selectAccount(account.id)
                            await reload()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.appleID).foregroundColor(.primary)
                                Text(account.teamName).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if accountID == account.id {
                                Image(systemName: "checkmark.circle.fill").accessibilityLabel("Selected for new installs")
                            }
                        }
                    }
                    .swipeActions {
                        SwiftUI.Button("Remove", role: .destructive) {
                            run {
                                try await SavedSigningAccounts.shared.remove(account.id)
                                await reload()
                            }
                        }
                    }
                }
                SwiftUI.Button {
                    run {
                        let result = try await AuthManager.shared.signIn(presentingViewController: presentingViewController,
                                                                        skipResign: !accounts.isEmpty, skipHowTos: true)
                        let saved = try await SavedSigningAccounts.shared.captureCurrentAccount(team: result.team, certificate: result.certificate)
                        if let saved {
                            try await SavedSigningAccounts.shared.selectAccount(saved.id)
                        }
                        await reload()
                    }
                } label: { Label("Add Apple account", systemImage: "person.badge.plus") }
            }
            Section(header: Text("Imported signing"), footer: Text("A usable identity includes a certificate, its matching private key, and a provisioning profile. Apple ID login is not required.")) {
                SwiftUI.Button { importing = true } label: {
                    Label("Import certificate and provisioning profile", systemImage: "square.and.arrow.down")
                }
                ForEach(profiles, id: \.uuid) { profile in
                    SwiftUI.Button {
                        run {
                            try await SavedSigningAccounts.shared.selectProfile(profile)
                            await reload()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name).foregroundColor(.primary)
                                Text(profile.bundleIdentifier).font(.caption).foregroundColor(.secondary)
                                Text(profile.expirationDate, style: .date).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: profileID == profile.uuid.uuidString ? "checkmark.circle.fill" : "doc.badge.gearshape")
                        }
                    }
                }
                NavigationLink(destination: CertificatesView(presentingViewController: presentingViewController)) {
                    Label("Certificates and private keys", systemImage: "key.fill")
                }
                NavigationLink(destination: ProfileManagementView(presentingViewController: presentingViewController)) {
                    Label("All provisioning profiles", systemImage: "doc.text.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Signing")
        .disabled(busy)
        .overlay { if busy { ProgressView().padding(24).background(.regularMaterial).cornerRadius(16) } }
        .task { await reload() }
        .sheet(isPresented: $importing, onDismiss: { Task { await reload() } }) {
            NavigationView { SigningImportView() }
        }
        .alert("Signing", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            SwiftUI.Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func reload() async {
        do {
            try await SavedSigningAccounts.shared.captureCurrentAccount()
            accounts = try await SavedSigningAccounts.shared.accounts()
            accountID = await SavedSigningAccounts.shared.selectedAccountID()
            if accountID == nil, await SavedSigningAccounts.shared.selectedProfileID() == nil {
                accountID = accounts.first { $0.appleID == AuthManager.shared.currentAppleID }?.id
            }
            profileID = await SavedSigningAccounts.shared.selectedProfileID()
            profiles = ProfileManager.shared.getAllLocalProfiles().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { errorMessage = error.localizedDescription }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            busy = true
            defer { busy = false }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct SigningImportView: View {
    private enum FileKind { case certificate, key, profile }
    @Environment(\.dismiss) private var dismiss
    @State private var certificateData: Data?
    @State private var keyData: Data?
    @State private var profileData: Data?
    @State private var certificateName = "Choose certificate or .p12"
    @State private var keyName = "Choose private key"
    @State private var profileName = "Choose .mobileprovision"
    @State private var password = ""
    @State private var fileKind = FileKind.certificate
    @State private var choosingFile = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var importTypes: [UTType] {
        let extensions: [String]
        switch fileKind {
        case .certificate: extensions = ["p12", "pfx", "pkcs12", "cer", "crt", "der", "pem"]
        case .key: extensions = ["key", "pem", "der"]
        case .profile: extensions = ["mobileprovision"]
        }
        return extensions.compactMap { UTType(filenameExtension: $0, conformingTo: .data) }
    }

    var body: some View {
        Form {
            Section(header: Text("1. Signing certificate"), footer: Text("Use a .p12/.pfx bundle, or a .cer/.crt/.der/.pem certificate with a separate private key.")) {
                SwiftUI.Button(certificateName) { choose(.certificate) }
                SecureField("Password for .p12 / .pfx", text: $password)
                    .textContentType(.password)
                if certificateData?.isPKCS12 != true {
                    SwiftUI.Button(keyName) { choose(.key) }
                }
            }
            Section(header: Text("2. Provisioning profile"), footer: Text("The profile must authorize this certificate, your device, and the app you want to sign.")) {
                SwiftUI.Button(profileName) { choose(.profile) }
            }
            Section {
                SwiftUI.Button("Import and use for new installs") { save() }
                    .disabled(certificateData == nil || profileData == nil || busy)
            }
        }
        .navigationTitle("Import signing identity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { SwiftUI.Button("Cancel") { dismiss() }.disabled(busy) } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: importTypes) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                switch fileKind {
                case .certificate: certificateData = data; certificateName = url.lastPathComponent; keyData = nil; keyName = "Choose private key"
                case .key: keyData = data; keyName = url.lastPathComponent
                case .profile: profileData = data; profileName = url.lastPathComponent
                }
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Could not import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            SwiftUI.Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .overlay { if busy { ProgressView().padding(24).background(.regularMaterial).cornerRadius(16) } }
    }

    private func choose(_ kind: FileKind) { fileKind = kind; choosingFile = true }

    private func save() {
        Task { @MainActor in
            busy = true
            defer { busy = false }
            do {
                guard let certificateData, let profileData else { return }
                let certificate: ALTCertificate
                if certificateData.isPKCS12 {
                    certificate = try ALTCertificate(p12Data: certificateData, password: password)
                } else {
                    guard let x509 = ALTX509Certificate(data: certificateData), let keyData else {
                        throw OperationError.invalidParameters("Select a valid certificate and its matching private key.")
                    }
                    certificate = ALTCertificate(x509: x509, privateKey: keyData)
                }
                let profile = try ALTProvisioningProfile(data: profileData)
                try ImportedSigningValidation.validate(profile, certificate: certificate, deviceID: Keychain.shared.deviceUDID)
                try CertificateManager.shared.storeCertificate(certificate)
                try ProfileManager.shared.importProfile(data: profileData)
                try await SavedSigningAccounts.shared.selectProfile(profile)
                password = ""; keyData = nil; self.certificateData = nil
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
#endif
