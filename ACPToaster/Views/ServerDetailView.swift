import SwiftUI
import AppKit

/// Detail for one selected server: its detected models, each with a Toast
/// button that generates its ACP wrapper, and a status bar along the bottom.
struct ServerDetailView: View {
    /// The server this detail is for.
    let server: Server

    /// Shared app state, owned by ContentView.
    @Environment(AppModel.self) private var appModel

    /// Detection state for this server.
    @State private var state = ServerState()
    /// Wrapper results, keyed by model ID.
    @State private var toasts: [String: WrapperGenerator.Result] = [:]
    /// The model ID currently being toasted, if any.
    @State private var toastingModelID: String?
    /// The message shown in the bottom status bar.
    @State private var statusMessage: ToastStatus?

    /// Used for the wrapper's exec line when no opencode binary is found.
    private static let fallbackOpencodePath = "/opt/homebrew/bin/opencode"

    var body: some View {
        VStack(spacing: 0) {
            // A plain inset List (not a grouped Form) so that per-row modifiers
            // like .listRowSeparator actually take effect, and the built-in
            // alternating row backgrounds give the Screen Sharing-style zebra.
            List {
                // The server's icon, large enough to span the server type and
                // detection status rows, beside them. (The icon is chosen in
                // the add/edit sheet.)
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
                        }
                    }
                    .listRowSeparator(.hidden)
                }

                // The models the server offers, each with its own Toast button.
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

            // The bottom status bar, built to match the sidebar's +/− bar height.
            statusBar
        }
        .navigationTitle(server.name)
        .task(id: server.id) {
            // Auto-detect when this server has never been checked.
            if state.status == .never {
                await detectAsync()
            }
            // Keep the ping (and model list) fresh: a lightweight models GET
            // every 5 seconds. The task is cancelled when the view goes away.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshAsync()
            }
        }
    }

    /// The detection status shown next to the Detect button.
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
                // The server kind has its own row above, so this is just
                // the count and the ping.
                Text("\(count) models · \(latencyText(latency))")
                    .foregroundStyle(.green)
            case .down(let message):
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Detection

    /// Starts a detection run in the background.
    private func detect() {
        Task { await detectAsync() }
    }

    /// Fetches the model list for this server and updates its state.
    private func detectAsync() async {
        guard !state.isDetecting, !state.isRefreshing else { return }
        state.isDetecting = true

        do {
            let list = try await ModelServerClient().fetchModels(from: server)
            state.models = list.models
            restoreToastedModels(list.models)
            state.kind = list.kind
            state.status = .up(count: list.models.count, latency: list.latency)
        } catch is CancellationError {
            return // The view went away mid-detection.
        } catch {
            state.status = .down(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        // Don't resurrect state for a server the user removed mid-flight.
        guard appModel.servers.contains(where: { $0.id == server.id }) else { return }
        state.isDetecting = false
    }

    /// A silent re-ping from the 5-second refresh loop: same fetch as a
    /// detection, but without the spinner so the status line just updates.
    private func refreshAsync() async {
        guard !state.isDetecting, !state.isRefreshing else { return }
        state.isRefreshing = true

        do {
            let list = try await ModelServerClient().fetchModels(from: server)
            state.models = list.models
            restoreToastedModels(list.models)
            state.kind = list.kind
            state.status = .up(count: list.models.count, latency: list.latency)
        } catch is CancellationError {
            return // The view went away mid-refresh.
        } catch {
            state.status = .down(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        state.isRefreshing = false
    }

    // MARK: - Toasting

    /// Starts a toast run for one model in the background. Toasts are
    /// serialized so two runs never write the OpenCode config at once.
    private func toast(_ model: ModelServerClient.ModelInfo) {
        guard toastingModelID == nil else { return }
        toastingModelID = model.id
        statusMessage = ToastStatus(kind: .working, text: "Toasting \(model.displayName ?? model.id)…")
        Task { await toastAsync(model) }
    }

    /// Locates opencode, merges this model into the OpenCode config, writes its
    /// wrapper, and refreshes the Xcode expert skill. Re-running is idempotent.
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

        // Write the wrapper, or record the config error.
        let result: WrapperGenerator.Result
        if let configError {
            result = WrapperGenerator.Result(selection: selection, wrapperPath: "", created: false, error: configError)
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

    /// Restores the "toasted" state for any model whose wrapper script already
    /// exists on disk, so models toasted in a previous session still show their
    /// expanded row (wrapper path, copy, delete) when the app reopens. The disk
    /// is the source of truth; toasts already in memory (e.g. a fresh one) win.
    private func restoreToastedModels(_ models: [ModelServerClient.ModelInfo]) {
        let fileManager = FileManager.default
        for model in models where toasts[model.id] == nil {
            let selection = AppModel.ModelSelection(serverID: server.id, modelID: model.id, displayName: model.displayName)
            let path = WrapperGenerator.wrapperPath(for: selection, server: server, homeDir: NSHomeDirectory())
            if fileManager.fileExists(atPath: path) {
                toasts[model.id] = WrapperGenerator.Result(selection: selection, wrapperPath: path, created: false, error: nil)
            }
        }
    }

    /// Deletes a toasted model's wrapper script and collapses its row back to
    /// just the model name and Toast button.
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

    /// A bar along the bottom of the detail, sized like the sidebar's +/− bar,
    /// that reports what the last action did.
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
            .padding(.vertical, 8)
        }
    }

    /// The icon + text for a status message, colored by its kind.
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

/// One model row: the display name (the row's primary text), a specs line
/// (params · quant · format · RAM · context), a capabilities line, and a
/// Toast button at the end. Once toasted, an expanded row holds the wrapper
/// path with right-aligned copy and delete buttons.
private struct ModelToastRow: View {
    let model: ModelServerClient.ModelInfo
    let result: WrapperGenerator.Result?
    /// True while this specific model is being toasted.
    let isToasting: Bool
    /// True while any model is being toasted (toasts are serialized).
    let isBusy: Bool
    let onToast: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // The model's info, stacked: name over specs over capabilities.
                // Apple's hierarchical text: headline for the primary label,
                // caption + secondary for the supporting lines, with a little
                // extra spacing between the lines.
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
            // The expanded row: the wrapper path with right-aligned copy and
            // delete buttons, or an error.
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

    /// The "params · quant · format · RAM · context" line, skipping any spec
    /// the server didn't report.
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

    /// The model's capabilities in a fixed, readable order.
    private var capabilities: [ModelServerClient.Capability] {
        ModelServerClient.Capability.allCases.filter { model.capabilities.contains($0) }
    }

    /// Formats a token count compactly: "128K", "1M".
    private static func contextText(_ length: Int) -> String {
        if length >= 1_000_000 {
            return String(format: "%.0fM", Double(length) / 1_000_000)
        }
        if length >= 1024 {
            return "\(length / 1024)K"
        }
        return "\(length)"
    }

    /// A small muted capsule label, e.g. "embedded" or "vision".
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

/// A message for the bottom status bar, colored by what kind of event it is.
private struct ToastStatus: Equatable {
    enum Kind: Equatable {
        case working
        case success
        case failure
    }
    var kind: Kind
    var text: String
}

/// Detection state for one server.
private struct ServerState {
    enum Status: Equatable {
        case never
        case up(count: Int, latency: Duration)
        case down(message: String)
    }

    var status: Status = .never
    var models: [ModelServerClient.ModelInfo] = []
    /// The server kind from the last successful check, for the status line.
    var kind: ModelServerClient.ServerKind?
    var isDetecting = false
    /// True while a background 5-second refresh is in flight.
    var isRefreshing = false
}

/// Formats a Duration as "X ms" or "X.X s".
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
