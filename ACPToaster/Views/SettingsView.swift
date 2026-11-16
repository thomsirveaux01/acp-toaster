import SwiftUI
import AppKit

/// The app's settings: a checker for OpenCode with an install button, and
/// the app's own version with a passive update check. Shown as the standard
/// Settings window (⌘, / toolbar gear).
struct SettingsView: View {
    /// The shared update checker, observed so the version row gains its
    /// Download button when a check finds a newer release.
    @ObservedObject var updater: UpdateChecker

    /// UserDefaults key for the last known OpenCode state, so the window can
    /// show it instantly on open and re-check in the background.
    private static let opencodeCacheKey = "acptoaster.toolchain.opencode"

    init(updater: UpdateChecker) {
        self._updater = ObservedObject(wrappedValue: updater)
        // Restore the last known result so the window shows it instantly;
        // the background check confirms or updates it in place.
        _opencodeState = State(initialValue: Self.cachedState(Self.opencodeCacheKey))
    }

    /// The official OpenCode installer, copied to the clipboard when
    /// Homebrew isn't available to install it.
    private static let opencodeInstallerCommand =
        "curl -fsSL https://opencode.ai/v2/install | bash"

    /// The installation state of one tool.
    private enum ToolState: Equatable, Codable {
        case checking
        case installed(version: String?)
        case notInstalled
    }

    @State private var opencodeState: ToolState = .checking
    // Whether Homebrew is present: it decides whether the OpenCode Install
    // button runs `brew install` or copies the curl installer command.
    @State private var brewAvailable = false
    @State private var isInstallingOpenCode = false
    @State private var openCodeInstallError: String?
    @State private var openCodeCommandCopied = false
    @State private var installTask: Task<Void, Never>?

    /// Re-checks when the window becomes active again, so an install done in
    /// Terminal (required for Homebrew) is picked up on the next switch back.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 28) {
            toolRow(label: "OpenCode:", state: opencodeState, caption: openCodeCaption, isError: openCodeCaptionIsError) {
                openCodeButton
            }
            versionRow
        }
        .padding(28)
        .frame(width: 520)
        .task {
            await check()
            // Passive update check: silent and throttled to once a day
            // inside the checker; the result shows up on the version row as
            // a Download button when a newer release exists.
            await updater.check(userInitiated: false)
        }
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
        // Top-aligned, like the Tailscale settings: the label and the button
        // line up with the status line, not the middle of the row.
        HStack(alignment: .top, spacing: 12) {
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

    /// The app's own version, laid out like the tool rows. When the passive
    /// check has found a newer release, a caption names it and a Download
    /// button appears at the trailing edge.
    private var versionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Version:")
                .fontWeight(.semibold)
                .frame(width: 100, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(updater.currentVersion)
                    if let build = Self.buildVersion {
                        Text("· build \(build)")
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .frame(width: 220, height: 18, alignment: .leading)
                // Always render one caption line (blank when there's nothing
                // to say) so the row's height stays constant.
                Text(updateCaption ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if updater.availableUpdate != nil {
                Button("Download") {
                    Task { await updater.downloadAvailableUpdate() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// The caption under the version: names the newer release when one is
    /// known to exist, regardless of whether the prompt was dismissed.
    private var updateCaption: String? {
        guard let release = updater.availableUpdate else { return nil }
        return "Version \(UpdateChecker.normalizedTag(release.tagName)) is available."
    }

    /// The build number (CFBundleVersion), for the "· build 21" suffix.
    private static var buildVersion: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    // MARK: - Captions

    private var openCodeCaption: String? {
        if isInstallingOpenCode { return "Installing via Homebrew…" }
        if let openCodeInstallError { return openCodeInstallError }
        guard openCodeMissing else { return nil }
        // Without Homebrew the button copies the official installer instead
        // of running it.
        guard brewAvailable else {
            return openCodeCommandCopied
                ? "Copied — paste it into Terminal."
                : "Homebrew isn't installed, so Install copies the official installer command — paste it into Terminal."
        }
        return nil
    }

    private var openCodeCaptionIsError: Bool {
        openCodeInstallError != nil
    }

    // MARK: - Buttons

    private var openCodeButton: some View {
        Button {
            if brewAvailable {
                installTask = Task { await installOpenCode() }
            } else {
                // No Homebrew: copy the official installer command instead.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.opencodeInstallerCommand, forType: .string)
                openCodeCommandCopied = true
            }
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
        // Grayed out while checking and while installing. Homebrew is no
        // longer a requirement: without it the button copies the command.
        .disabled(!openCodeMissing || isInstallingOpenCode)
    }

    // MARK: - State helpers

    private var openCodeMissing: Bool {
        if case .notInstalled = opencodeState { return true }
        return false
    }

    // MARK: - Actions

    /// Checks for OpenCode and reports the result. The previous result stays
    /// visible while the check runs, so nothing pops in.
    private func check() async {
        async let detection = OpencodeLocator().detect()
        // Homebrew is only a presence check: it decides whether the Install
        // button runs brew or copies the curl installer.
        brewAvailable = BrewService.brewPath() != nil
        let result = await detection
        switch result {
        case .found(_, let version):
            opencodeState = .installed(version: version)
        case .notFound:
            opencodeState = .notInstalled
        }
        Self.saveState(opencodeState, Self.opencodeCacheKey)
    }

    /// The last known state for a tool, or .checking on the very first run.
    private static func cachedState(_ key: String) -> ToolState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ToolState.self, from: data) else {
            return .checking
        }
        return state
    }

    private static func saveState(_ state: ToolState, _ key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
    SettingsView(updater: UpdateChecker())
}
