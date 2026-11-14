import SwiftUI
import AppKit

/// First-run setup: make sure OpenCode is installed.
struct SetupStepView: View {
    /// Called when OpenCode is found. In the first-run flow this advances the
    /// app into the main window.
    var onFound: () -> Void = {}

    /// UserDefaults key marking first-run setup as complete.
    static let setupCompleteKey = "acptoaster.setupComplete"

    /// Homebrew's installer needs sudo, which a GUI app should not prompt for.
    private static let brewInstallerCommand =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    private enum Phase: Equatable {
        case checking
        case found(path: String, version: String?)
        case notFound(brewAvailable: Bool)
        case installing
        case installFailed(exitStatus: Int32)
    }

    @State private var phase: Phase = .checking
    @State private var logLines: [String] = []
    @State private var installTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .checking:
                ProgressView("Looking for OpenCode…")
                    .controlSize(.large)
            case .found(let path, let version):
                foundView(path: path, version: version)
            case .notFound(let brewAvailable):
                notFoundView(brewAvailable: brewAvailable)
            case .installing:
                installingView()
            case .installFailed(let exitStatus):
                installFailedView(exitStatus: exitStatus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await check() }
        .onDisappear { installTask?.cancel() }
    }

    // MARK: - States

    private func foundView(path: String, version: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("OpenCode is installed")
                .font(.title3.bold())
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Path", value: path)
                if let version {
                    LabeledContent("Version", value: version)
                }
            }
            .font(.callout)
            Text("Setup complete — continue to configure your model servers.")
                .foregroundStyle(.secondary)
        }
    }

    private func notFoundView(brewAvailable: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("OpenCode was not found on this Mac.")
                .font(.title3.bold())
            if brewAvailable {
                Text("You can install it with Homebrew, right from here.")
                    .foregroundStyle(.secondary)
                Button {
                    installTask = Task { await install() }
                } label: {
                    Label("Install OpenCode", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Homebrew was not found either, so ACP Toaster can't install OpenCode for you. Install Homebrew first by pasting this into Terminal:")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                commandRow
                Button("Re-check") {
                    Task { await check() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func installingView() -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Installing OpenCode via Homebrew…")
                    .font(.title3.bold())
            }
            logView
            HStack {
                Button("Install OpenCode") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                Button("Cancel") {
                    installTask?.cancel()
                }
            }
        }
    }

    private func installFailedView(exitStatus: Int32) -> some View {
        VStack(spacing: 12) {
            Label("Install failed (exit status \(exitStatus))", systemImage: "xmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.red)
            logView
            HStack {
                Button("Try again") {
                    installTask = Task { await install() }
                }
                Button("Re-check") {
                    Task { await check() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Pieces

    /// The Homebrew installer one-liner with a copy button.
    private var commandRow: some View {
        HStack(spacing: 8) {
            Text(Self.brewInstallerCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.brewInstallerCommand, forType: .string)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Monospaced install log that stays pinned to the bottom.
    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .textSelection(.enabled)
                    }
                    // Invisible anchor used for auto-scrolling.
                    Color.clear
                        .frame(height: 1)
                        .id("log-bottom")
                }
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(height: 260)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .onAppear { proxy.scrollTo("log-bottom", anchor: .bottom) }
            .onChange(of: logLines) {
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Actions

    /// Runs the locator and updates the phase.
    private func check() async {
        phase = .checking
        switch await OpencodeLocator().detect() {
        case .found(let path, let version):
            UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
            phase = .found(path: path, version: version)
            onFound()
        case .notFound:
            phase = .notFound(brewAvailable: BrewService.brewPath() != nil)
        }
    }

    /// Runs `brew install opencode`, streaming output, then re-checks.
    private func install() async {
        logLines = []
        phase = .installing
        let install = BrewService().install()
        for await line in install.lines {
            logLines.append(line)
        }
        if Task.isCancelled {
            // The user cancelled: back to the "not found" state.
            phase = .notFound(brewAvailable: true)
            return
        }
        if install.exitStatus == 0 {
            await check()
        } else {
            phase = .installFailed(exitStatus: install.exitStatus)
        }
    }
}

#Preview {
    SetupStepView()
}
