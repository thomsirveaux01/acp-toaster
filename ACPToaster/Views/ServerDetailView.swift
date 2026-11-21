import SwiftUI
import AppKit

/// One server's detail: detected models with Toast buttons, and a bottom status bar.
struct ServerDetailView: View {
    let server: Server

    @Environment(AppModel.self) private var appModel

    @State private var state = ServerState()
    @State private var toasts: [String: WrapperGenerator.Result] = [:]
    @State private var toastingModelID: String?
    @State private var statusMessage: ToastStatus?

    /// Used for the wrapper's exec line when no opencode binary is found.
    private static let fallbackOpencodePath = "/opt/homebrew/bin/opencode"

    var body: some View {
        VStack(spacing: 0) {
            // A plain inset List (not a grouped Form) so per-row modifiers like .listRowSeparator take effect and the built-in zebra shows.
            List {
                // The icon is chosen in the add/edit sheet.
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: server.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            if let kind = state.kind {
                                Text("Server type: \(kind.rawValue)")
                                    .font(.headline)
                            }
                            HStack {
                                statusLabel
                                Spacer()
                                Button {
                                    detect()
                                } label: {
                                    Label("Detect", systemImage: "antenna.radiowaves.left.and.right")
                                }
                                .disabled(state.isDetecting)
                            }
                            if state.kind != nil {
                                Text("In Xcode 27, navigate to the Intelligence settings, click Add an Agent, and paste the wrapper into the Executable field.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                }

                if case .up = state.status {
                    Section {
                        ForEach(state.models) { model in
                            ModelToastRow(
                                model: model,
                                result: toasts[model.id],
                                isToasting: toastingModelID == model.id,
                                isBusy: toastingModelID != nil,
                                onToast: { toast(model) },
                                onDelete: { deleteWrapper(model) }
                            )
                        }
                    } header: {
                        Text("Models")
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()

            // Sized to match the sidebar's +/− bar.
            statusBar
        }
        .navigationTitle(server.name)
        .task(id: server.id) {
            if state.status == .never {
                await fetch(silent: false)
            }
            // Keep the ping and model list fresh: a models GET every 5 seconds.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if state.isDetecting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Detecting…")
                    .foregroundStyle(.secondary)
            }
        } else {
            switch state.status {
            case .never:
                Text("Not checked yet")
                    .foregroundStyle(.secondary)
            case .up(let count, let latency):
                // The kind has its own row above; this is just the count and the ping.
                Text("\(count) models · Ping: \(latencyText(latency))")
                    .foregroundStyle(.green)
            case .down(let message):
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Detection

    private func detect() {
        Task { await fetch(silent: false) }
    }

    /// A silent re-ping from the 5-second refresh loop: no spinner, so the status line just updates.
    private func refresh() async {
        await fetch(silent: true)
    }

    private func fetch(silent: Bool) async {
        guard !state.isDetecting, !state.isRefreshing else { return }
        state.isDetecting = !silent
        state.isRefreshing = silent

        do {
            let list = try await ModelServerClient().fetchModels(from: server)
            state.models = list.models
            restoreToastedModels(list.models)
            state.kind = list.kind
            state.status = .up(count: list.models.count, latency: list.latency)
        } catch is CancellationError {
            return // The view went away mid-fetch.
        } catch {
            state.status = .down(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        // Don't resurrect state for a server the user removed mid-flight.
        guard appModel.servers.contains(where: { $0.id == server.id }) else { return }
        state.isDetecting = false
        state.isRefreshing = false
    }

    // MARK: - Toasting

    /// Starts a toast run; toasts are serialized so two runs never write the OpenCode config at once.
    private func toast(_ model: ModelServerClient.ModelInfo) {
        guard toastingModelID == nil else { return }
        toastingModelID = model.id
        statusMessage = ToastStatus(kind: .working, text: "Toasting \(model.displayName ?? model.id)…")
        Task { await toastAsync(model) }
    }

    /// Re-running is idempotent.
    private func toastAsync(_ model: ModelServerClient.ModelInfo) async {
        let selection = AppModel.ModelSelection(serverID: server.id, modelID: model.id, displayName: model.displayName)

        let opencodePath: String
        switch await OpencodeLocator().detect() {
        case .found(let path, _):
            opencodePath = path
        case .notFound:
            opencodePath = Self.fallbackOpencodePath
        }

        // Merge the OpenCode config for this model; the merge preserves any
        // other models already toasted for this server.
        var configError: String?
        do {
            try OpenCodeConfigStore().ensureProvider(server: server, models: [selection])
        } catch {
            configError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        let result: WrapperGenerator.Result
        if let configError {
            result = WrapperGenerator.Result(selection: selection, wrapperPath: "", error: configError)
        } else {
            result = WrapperGenerator().generate(for: selection, server: server, opencodePath: opencodePath, homeDir: NSHomeDirectory())
        }
        toasts[model.id] = result

        // Make sure the agents can consult Apple's Xcode expert references.
        let expert = ExpertSkillInstaller().install()

        if let error = result.error {
            statusMessage = ToastStatus(kind: .failure, text: error)
        } else {
            // The wrapper path is already shown in the model's expanded row,
            // so the status bar just celebrates the toast.
            var text = "Toasted!"
            if expert.isFailure {
                text += "  ·  \(expert.message)"
            }
            statusMessage = ToastStatus(kind: .success, text: text)
        }

        toastingModelID = nil
    }

    /// Restores toasted state from wrapper scripts on disk, so models toasted in a previous session reopen expanded; in-memory toasts win.
    private func restoreToastedModels(_ models: [ModelServerClient.ModelInfo]) {
        let fileManager = FileManager.default
        for model in models where toasts[model.id] == nil {
            let selection = AppModel.ModelSelection(serverID: server.id, modelID: model.id, displayName: model.displayName)
            let path = WrapperGenerator.wrapperPath(for: selection, server: server, homeDir: NSHomeDirectory())
            if fileManager.fileExists(atPath: path) {
                toasts[model.id] = WrapperGenerator.Result(selection: selection, wrapperPath: path, error: nil)
            }
        }
    }

    /// Deletes a toasted model's wrapper script.
    private func deleteWrapper(_ model: ModelServerClient.ModelInfo) {
        guard let result = toasts[model.id], !result.wrapperPath.isEmpty else { return }
        let path = result.wrapperPath
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            toasts[model.id] = nil
            statusMessage = ToastStatus(kind: .success, text: "Deleted wrapper · \(path)")
        } catch {
            statusMessage = ToastStatus(kind: .failure, text: "Couldn't delete wrapper: \(error.localizedDescription)")
        }
    }

    // MARK: - Status bar

    /// Reports what the last action did.
    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if let statusMessage {
                    statusView(statusMessage)
                } else {
                    Text("Ready")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            // 31pt + the 1pt divider: a 32pt strip matching the sidebar's
            // +/− bar.
            .frame(height: 31)
        }
    }

    @ViewBuilder
    private func statusView(_ status: ToastStatus) -> some View {
        switch status.kind {
        case .working:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(status.text)
                    .foregroundStyle(.secondary)
            }
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(status.text)
                    .foregroundStyle(.secondary)
            }
        case .failure:
            Label(status.text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Model row

/// One model row: name, specs, capabilities, and a Toast button; once toasted, an expanded row holds the wrapper path with copy and delete.
private struct ModelToastRow: View {
    let model: ModelServerClient.ModelInfo
    let result: WrapperGenerator.Result?
    let isToasting: Bool
    /// True while any model is being toasted (toasts are serialized).
    let isBusy: Bool
    let onToast: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // Apple's hierarchical text: headline for the primary label, caption + secondary for the supporting lines.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(model.displayName ?? model.id)
                            .font(.headline)
                            .lineLimit(1)
                        if model.isEmbedding {
                            badge("embedded")
                        }
                    }
                    if !specParts.isEmpty {
                        Text(specParts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !capabilities.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(capabilities, id: \.self) { capability in
                                badge(capability.rawValue)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    onToast()
                } label: {
                    // The text stays in the layout (hidden while toasting) so the
                    // button keeps its size; the spinner takes its place.
                    ZStack {
                        Text("Toast")
                            .opacity(isToasting ? 0 : 1)
                        if isToasting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
            if let result {
                if let error = result.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    HStack(spacing: 8) {
                        Text(result.wrapperPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Copy") {
                            copyToPasteboard(result.wrapperPath)
                        }
                        .controlSize(.small)
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                        .help("Delete wrapper")
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    private var specParts: [String] {
        var parts: [String] = []
        if let params = model.params { parts.append(params) }
        if let quantization = model.quantization { parts.append(quantization) }
        if let format = model.format { parts.append(format) }
        if let sizeBytes = model.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .memory))
        }
        if let maxContextLength = model.maxContextLength {
            parts.append("\(Self.contextText(maxContextLength)) ctx")
        }
        return parts
    }

    private var capabilities: [ModelServerClient.Capability] {
        ModelServerClient.Capability.allCases.filter { model.capabilities.contains($0) }
    }

    private static func contextText(_ length: Int) -> String {
        if length >= 1_000_000 {
            return String(format: "%.0fM", Double(length) / 1_000_000)
        }
        if length >= 1024 {
            return "\(length / 1024)K"
        }
        return "\(length)"
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Support

private struct ToastStatus: Equatable {
    enum Kind: Equatable {
        case working
        case success
        case failure
    }
    var kind: Kind
    var text: String
}

private struct ServerState {
    enum Status: Equatable {
        case never
        case up(count: Int, latency: Duration)
        case down(message: String)
    }

    var status: Status = .never
    var models: [ModelServerClient.ModelInfo] = []
    var kind: ModelServerClient.ServerKind?
    var isDetecting = false
    var isRefreshing = false
}

private func latencyText(_ latency: Duration) -> String {
    let components = latency.components
    // 1 ms = 1e15 attoseconds.
    let milliseconds = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    if milliseconds < 1000 {
        return "\(milliseconds) ms"
    }
    return String(format: "%.1f s", Double(milliseconds) / 1000)
}

#Preview {
    ServerDetailView(
        server: Server(name: "LM Studio", baseURL: URL(string: "http://127.0.0.1:1234/v1")!)
    )
    .environment(AppModel())
}
