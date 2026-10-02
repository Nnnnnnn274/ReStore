#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct LiveContainerView: View {
    @StateObject private var container = BuiltInLiveContainer()
    @State private var search = ""
    @State private var importing = false
    @State private var deleting: ContainerApp?
    private let columns = [GridItem(.adaptive(minimum: 94), spacing: 22)]

    private var apps: [ContainerApp] {
        container.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleIdentifier.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your app library").font(.title2.bold())
                        Text("\(container.apps.count) apps · Built into ReStore").font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(20).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(24)
                if apps.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: search.isEmpty ? "square.grid.2x2" : "magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
                        Text(search.isEmpty ? "Make room for your apps" : "No matching apps").font(.headline)
                        Text(search.isEmpty ? "Import an IPA to add it to your built-in container library." : "Try a different name.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        if search.isEmpty { SwiftUI.Button("Import IPA") { importing = true }.buttonStyle(.borderedProminent) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(apps) { app in
                            SwiftUI.Button { container.open(app) } label: {
                                VStack(spacing: 8) {
                                    Group {
                                        if let icon = app.icon { Image(uiImage: icon).resizable().scaledToFit() }
                                        else { Image(systemName: "app.fill").resizable().scaledToFit().foregroundColor(.blue).padding(14) }
                                    }
                                    .frame(width: 70, height: 70).background(Color(uiColor: .tertiarySystemGroupedBackground)).cornerRadius(17)
                                    Text(app.name).font(.caption).foregroundColor(.primary).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 108, alignment: .top)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(app.name)")
                            .contextMenu {
                                SwiftUI.Button { container.open(app) } label: { Label("Open", systemImage: "play.fill") }
                                Text(app.bundleIdentifier)
                                Text("Version \(app.version)")
                                SwiftUI.Button(role: .destructive) { deleting = app } label: { Label("Delete app and data", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("LiveContainer")
        .searchable(text: $search, prompt: "Search apps")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { SwiftUI.Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import IPA") } }
        .disabled(container.isBusy)
        .overlay { if container.isBusy { ProgressView("Preparing app…").padding(24).background(.regularMaterial).cornerRadius(20) } }
        .onAppear { container.reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .archive]) { result in
            switch result {
            case .success(let url): Task { await container.importApp(from: url) }
            case .failure(let error): container.errorMessage = error.localizedDescription
            }
        }
        .alert("LiveContainer", isPresented: Binding(get: { container.errorMessage != nil }, set: { if !$0 { container.errorMessage = nil } })) {
            SwiftUI.Button("OK", role: .cancel) { container.errorMessage = nil }
        } message: { Text(container.errorMessage ?? "") }
        .confirmationDialog("Delete \(deleting?.name ?? "app") and its data?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            SwiftUI.Button("Delete app and data", role: .destructive) { if let deleting { container.delete(deleting) }; deleting = nil }
            SwiftUI.Button("Cancel", role: .cancel) { deleting = nil }
        }
    }
}
#endif
