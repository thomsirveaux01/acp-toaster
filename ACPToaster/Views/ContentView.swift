import SwiftUI

/// Main window: first-run setup, then a Screen-Sharing-style split view with
/// the server list in the sidebar and the selected server's detail on the right.
struct ContentView: View {
    /// Shared app state, owned by this view.
    @State private var appModel = AppModel()

    /// First-run setup is complete once OpenCode has been found at least once.
    @State private var setupComplete = UserDefaults.standard.bool(forKey: SetupStepView.setupCompleteKey)

    /// The server currently selected in the sidebar.
    @State private var selectedServerID: UUID?
    /// The server being edited in the sheet; nil means adding a new one.
    @State private var editorServer: Server?
    @State private var showEditor = false
    @State private var showSetupSheet = false

    var body: some View {
        Group {
            if setupComplete {
                mainFlow
            } else {
                // First launch: setup owns the whole window until OpenCode is
                // found, then the main flow appears in its place.
                SetupStepView(onFound: { setupComplete = true })
                    .padding(20)
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            SetupStepView()
                .frame(minWidth: 560, minHeight: 480)
        }
        .frame(minWidth: 640, minHeight: 480)
        .environment(appModel)
    }

    /// The split window shown after first-run setup.
    private var mainFlow: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showEditor) {
            ServerEditorSheet(server: editorServer) { newServer in
                // In add mode, select the new server; in edit mode it's already selected.
                if editorServer == nil {
                    selectedServerID = newServer.id
                }
            }
        }
        .onAppear { selectFirstIfNone() }
        .onChange(of: appModel.servers) { clearStaleSelection() }
    }

    /// The sidebar: the server list with a +/− bottom bar.
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
                        editorServer = server
                        showEditor = true
                    }
                }
            }
            .navigationTitle("Servers")

            // macOS has no `.bottomBar` toolbar placement, so the source-list
            // bottom bar is built by hand to match the system look.
            Divider()
            HStack(spacing: 0) {
                Button {
                    editorServer = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28)
                }
                .help("Add a server")
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

    /// The detail: the selected server, or a prompt to pick one.
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

    /// The completed first-run setup, tucked away behind a toolbar button.
    private var setupButton: some View {
        Button {
            showSetupSheet = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("OpenCode setup")
    }

    /// Selects the first server on appear when nothing is selected.
    private func selectFirstIfNone() {
        guard selectedServerID == nil else { return }
        if let first = appModel.servers.first {
            selectedServerID = first.id
        }
    }

    /// Clears the selection when the selected server has been removed.
    private func clearStaleSelection() {
        guard let current = selectedServerID,
              !appModel.servers.contains(where: { $0.id == current }) else { return }
        selectedServerID = nil
    }
}

#Preview {
    ContentView()
}
