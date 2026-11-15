import SwiftUI
import AppKit

/// The app's settings: checkers for the local toolchain (Homebrew and
/// OpenCode) with install buttons. Shown both as the first-run gate inside
/// the main window and as the standard Settings window (⌘, / toolbar gear).
struct SettingsView: View {
    /// Called when OpenCode is found. In the first-run flow this advances
    /// the app into the main window; the Settings window ignores it.
    var onFound: () -> Void = {}

    /// UserDefaults key marking first-run setup as complete.
    static let setupCompleteKey = "acptoaster.setupComplete"

    /// Homebrew's installer needs sudo, which a GUI app should not prompt
    /// for, so the Homebrew "Install" button copies this one-liner instead.
    private static let brewInstallerCommand =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    /// The installation state of one tool.
    private enum ToolState: Equatable {
        case checking
        case installed(version: String?)
        case notInstalled
    }

    @State private var brewState: ToolState = .checking
    @State private var opencodeState: ToolState = .checking
    @State private var isInstallingOpenCode = false
    @State private var openCodeInstallError: String?
    @State private var brewCommandCopied = false
    @State private var installTask: Task<Void, Never>?

    /// Re-checks when the window becomes active again, so an install done in
    /// Terminal (required for Homebrew) is picked up on the next switch back.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 28) {
            toolRow(label: "Homebrew:", state: brewState, caption: brewCaption, isError: false) {
                brewButton
            }
            toolRow(label: "OpenCode:", state: opencodeState, caption: openCodeCaption, isError: openCodeCaptionIsError) {
                openCodeButton
            }
        }
        .padding(28)
        .frame(width: 520)
        .task { await check() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await check() }
            }
        }
        .onDisappear { installTask?.cancel() }
    }

    // MARK: - Rows

    /// One Tailscale-style settings row: a right-aligned bold label, the
    /// tool's status, a caption line, and a trailing button. The status and
    /// caption areas have fixed sizes, so nothing moves while the check runs
    /// and the results appear in place.
    private func toolRow<Trailing: View>(
        label: String,
        state: ToolState,
        caption: String?,
        isError: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 100, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                statusLine(for: state)
                    .frame(width: 220, height: 18, alignment: .leading)
                // Always render one caption line (blank when there's nothing
                // to say) so the row's height stays constant.
                Text(caption ?? " ")
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
            }
            Spacer()
            trailing()
        }
    }

    /// The status line. While checking it's empty — the check runs silently
    /// and the result appears in the reserved space without moving anything.
    @ViewBuilder
    private func statusLine(for state: ToolState) -> some View {
        switch state {
        case .checking:
            EmptyView()
        case .installed(let version):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Installed")
                if let version {
                    Text("· \(version)")
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        case .notInstalled:
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                Text("Not installed")
            }
        }
    }

    // MARK: - Captions

    private var brewCaption: String? {
        guard brewMissing else { return nil }
        return brewCommandCopied
            ? "Copied — paste it into Terminal."
            : "The installer needs sudo, so Install copies the command — paste it into Terminal."
    }

    private var openCodeCaption: String? {
        if isInstallingOpenCode { return "Installing via Homebrew…" }
        if let openCodeInstallError { return openCodeInstallError }
        guard openCodeMissing else { return nil }
        return brewInstalled ? nil : "Install Homebrew first."
    }

    private var openCodeCaptionIsError: Bool {
        openCodeInstallError != nil
    }

    // MARK: - Buttons

    private var brewButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.brewInstallerCommand, forType: .string)
            brewCommandCopied = true
        } label: {
            Text("Install")
        }
        // Grayed out while checking and when Homebrew is already installed.
        .disabled(!brewMissing)
    }

    private var openCodeButton: some View {
        Button {
            installTask = Task { await installOpenCode() }
        } label: {
            if isInstallingOpenCode {
                // Keep the button's size constant while the spinner spins.
                ZStack {
                    Text("Install").opacity(0)
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Text("Install")
            }
        }
        // Grayed out while checking, while installing, when OpenCode is
        // already installed, or when Homebrew is missing (it's the installer).
        .disabled(!openCodeMissing || isInstallingOpenCode || !brewInstalled)
    }

    // MARK: - State helpers

    private var brewInstalled: Bool {
        if case .installed = brewState { return true }
        return false
    }

    private var openCodeInstalled: Bool {
        if case .installed = opencodeState { return true }
        return false
    }

    /// True only once the check has completed and the tool is missing.
    private var brewMissing: Bool {
        if case .notInstalled = brewState { return true }
        return false
    }

    private var openCodeMissing: Bool {
        if case .notInstalled = opencodeState { return true }
        return false
    }

    // MARK: - Actions

    /// Checks both tools concurrently and reports the results.
    private func check() async {
        brewState = .checking
        opencodeState = .checking
        brewCommandCopied = false
        openCodeInstallError = nil
        async let brewVersion = BrewService.brewVersion()
        async let detection = OpencodeLocator().detect()
        let (version, result) = await (brewVersion, detection)
        brewState = version.map(ToolState.installed) ?? .notInstalled
        switch result {
        case .found(_, let version):
            opencodeState = .installed(version: version)
        case .notFound:
            opencodeState = .notInstalled
        }
        if openCodeInstalled {
            // First-run gate: OpenCode is present, so setup is complete.
            UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
            onFound()
        }
    }

    /// Runs `brew install opencode`, then re-checks.
    private func installOpenCode() async {
        isInstallingOpenCode = true
        let install = BrewService().install()
        for await _ in install.lines {
            // The log is intentionally not shown; the spinner is the feedback.
        }
        guard !Task.isCancelled else {
            isInstallingOpenCode = false
            return
        }
        isInstallingOpenCode = false
        if install.exitStatus == 0 {
            await check()
        } else {
            openCodeInstallError = "Install failed (exit status \(install.exitStatus))."
        }
    }
}

#Preview {
    SettingsView()
}
