import SwiftUI

/// Main window: the first-run wizard, then a Screen-Sharing-style split view (server list sidebar, selected server detail).
struct ContentView: View {
    @State private var appModel = AppModel()

    /// The update checker, owned by the App so the menu and the window share it.
    /// Defaulted so the preview compiles without owning one.
    @ObservedObject var updater: UpdateChecker = UpdateChecker()

    /// True once the first-run wizard has been finished or skipped.
    @State private var setupComplete = UserDefaults.standard.bool(forKey: FirstRunView.setupCompleteKey)

    @State private var selectedServerID: UUID?

    /// What the editor sheet is showing; driving it with `.sheet(item:)` guarantees the sheet sees the current value (a separate `isPresented` + optional could present a stale `nil`).
    private enum EditorSheet: Identifiable {
        case add
        case edit(Server)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let server): server.id.uuidString
            }
        }
    }
    @State private var editorSheet: EditorSheet?

    var body: some View {
        Group {
            if setupComplete {
                mainFlow
            } else {
                FirstRunView(
                    onFinish: { setupComplete = true },
                    onAddServer: {
                        // Finish the wizard and drop straight into the
                        // add-server sheet in the main window.
                        setupComplete = true
                        editorSheet = .add
                    }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { await updater.check(userInitiated: false) }
        // The status popups ride the stock alert; the available-prompt is a sheet because alerts can't scroll long release notes.
        .alert(alertTitle, isPresented: statusShown, actions: { alertButtons }, message: {
            Text(alertMessage)
        })
        .sheet(isPresented: updateShown) {
            if case let .available(version, notes) = updater.prompt {
                UpdatePromptView(version: version, notes: notes,
                                 onDownload: { Task { await updater.downloadPromptedUpdate() } },
                                 onSkip: { updater.skipPromptedVersion() },
                                 onLater: { updater.prompt = nil })
            }
        }
        .environment(appModel)
    }

    // MARK: - Update prompt

    private var statusShown: Binding<Bool> {
        Binding(get: {
            if case .available = updater.prompt { return false }
            return updater.prompt != nil
        }, set: { if !$0 { updater.prompt = nil } })
    }

    private var updateShown: Binding<Bool> {
        Binding(get: {
            if case .available = updater.prompt { return true }
            return false
        }, set: { if !$0 { updater.prompt = nil } })
    }

    private var alertTitle: String {
        switch updater.prompt {
        case .available: ""
        case .upToDate: "You’re Up to Date"
        case .checkFailed: "Update Check Failed"
        case nil: ""
        }
    }

    private var alertMessage: String {
        switch updater.prompt {
        case .available:
            return ""
        case .upToDate:
            return "Version \(updater.currentVersion) is the latest release."
        case .checkFailed:
            // Vague on purpose: covers dead networks, rate limits, and a 404
            // (no release published yet) alike.
            return "Couldn't check for updates. Try again later."
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var alertButtons: some View {
        Button("OK", role: .cancel) {}
    }

    private var mainFlow: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $editorSheet) { sheet in
            switch sheet {
            case .add:
                // In add mode, select the new server once it's saved.
                ServerEditorSheet { newServer in
                    selectedServerID = newServer.id
                }
            case .edit(let server):
                // In edit mode the server is already selected.
                ServerEditorSheet(server: server) { _ in }
            }
        }
        .onAppear { selectFirstIfNone() }
        .onChange(of: appModel.servers) { clearStaleSelection() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedServerID) {
                ForEach(appModel.servers) { server in
                    HStack(spacing: 8) {
                        // The server's chosen glyph; a fixed width keeps the
                        // text column aligned across differently-shaped icons.
                        Image(systemName: server.icon)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            Text(server.hostPort)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(server.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editorSheet = .edit(server)
                    }
                }
            }
            .navigationTitle("Servers")

            // macOS has no `.bottomBar` toolbar placement, so the source-list
            // bottom bar is built by hand to match the system look.
            Divider()
            HStack(spacing: 0) {
                Button {
                    editorSheet = .add
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28)
                }
                .help("Add server")
                Divider()
                    .frame(height: 16)
                Button {
                    if let selectedServerID {
                        appModel.removeServer(selectedServerID)
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28)
                }
                .help("Remove the selected server")
                .disabled(selectedServerID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(200)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let selectedServerID,
               let server = appModel.servers.first(where: { $0.id == selectedServerID }) {
                ServerDetailView(server: server)
                    // Full-value identity: editing the server resets the detail
                    // so it re-detects with the new name/address.
                    .id(server)
            } else {
                ContentUnavailableView(
                    "Select a server",
                    systemImage: "network",
                    description: Text("Pick a server from the sidebar, or add one with the + button.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                setupButton
            }
        }
    }

    private var setupButton: some View {
        SettingsLink {
            Image(systemName: "gearshape")
        }
        .help("Settings")
    }

    private func selectFirstIfNone() {
        guard selectedServerID == nil else { return }
        if let first = appModel.servers.first {
            selectedServerID = first.id
        }
    }

    private func clearStaleSelection() {
        guard let current = selectedServerID,
              !appModel.servers.contains(where: { $0.id == current }) else { return }
        selectedServerID = nil
    }
}

/// Update-available sheet; the notes are capped to a scrollable height so a long list can't break the window.
struct UpdatePromptView: View {
    let version: String
    let notes: String
    var onDownload: () -> Void
    var onSkip: () -> Void
    var onLater: () -> Void

    // GitHub note bodies are markdown bullets; the dialog renders real ones.
    var bullets: [String] {
        notes.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version \(version) is available!")
                .font(.headline)
            if !bullets.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(bullets, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(line)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            HStack {
                Spacer()
                Button("Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button("Skip This Version", action: onSkip)
                Button("Download", action: onDownload)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

#Preview {
    ContentView()
}
