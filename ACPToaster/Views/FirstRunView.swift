import SwiftUI
import AppKit

/// The first-run wizard (welcome, install OpenCode, add a server); it owns the window until finished or skipped, after which OpenCode status lives in Settings.
struct FirstRunView: View {
    var onFinish: () -> Void

    /// Called when the user taps "Add a server" on the last screen: the
    /// wizard ends and the main window opens the add-server sheet.
    var onAddServer: () -> Void = {}

    enum Screen {
        case welcome
        case installOpenCode
        case addServer
    }

    /// How the wizard checks for OpenCode. Defaulted so probes can inject a
    /// fixed result.
    var detectOpenCode: () async -> OpencodeLocator.Detection = {
        await OpencodeLocator().detect()
    }

    static let setupCompleteKey = "acptoaster.setupComplete"

    @State private var screen: Screen
    // OpenCode's version while on the install screen; nil means not installed yet.
    @State private var opencodeVersion: String?
    @State private var brewCommandCopied = false
    @State private var openCodeCommandCopied = false

    init(onFinish: @escaping () -> Void,
         // Where the wizard starts. Defaulted so the production call site
         // stays clean; probes start on a specific screen.
         initialScreen: Screen = .welcome,
         detectOpenCode: @escaping () async -> OpencodeLocator.Detection = { await OpencodeLocator().detect() },
         onAddServer: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        self.detectOpenCode = detectOpenCode
        self.onAddServer = onAddServer
        _screen = State(initialValue: initialScreen)
    }

    var body: some View {
        VStack(spacing: 24) {
            switch screen {
            case .welcome:
                welcomeScreen
            case .installOpenCode:
                installOpenCodeScreen
            case .addServer:
                addServerScreen
            }
            Spacer(minLength: 0)
            navigationButtons
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: screen) {
            // Only the install screen polls: check immediately, then every
            // five seconds until OpenCode appears, then stop.
            guard screen == .installOpenCode else { return }
            while !Task.isCancelled {
                if case .found(_, let version) = await detectOpenCode() {
                    opencodeVersion = version
                    return
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Screens

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Welcome to ACP Toaster!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("ACP Toaster makes it easy to use third-party AI agents, including self-hosted agents, in Xcode 27. Using OpenCode, connect to any MCP server and create a wrapper that can be plugged into Xcode and use its native agent skills.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
        }
    }

    private var installOpenCodeScreen: some View {
        VStack(spacing: 20) {
            Text("Install OpenCode")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("To use ACP Toaster, you'll need OpenCode installed on the Mac that you use to run Xcode. Installing via the Homebrew package manager is recommended.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            // Both states reserve the same area so the switch between them
            // doesn't move the header.
            if let opencodeVersion {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Installed")
                    Text("· \(opencodeVersion)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    commandRow(label: "Install Homebrew (if you don't have it):",
                               command: BrewService.installerCommand,
                               copied: $brewCommandCopied)
                    commandRow(label: "Install OpenCode:",
                               command: BrewService.opencodeInstallCommand,
                               copied: $openCodeCommandCopied)
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            }
        }
    }

    /// One install command; the caption line stays (blank until copied) so the row's height is constant.
    private func commandRow(label: String, command: String, copied: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .fontWeight(.semibold)
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied.wrappedValue = true
                }
                .controlSize(.small)
            }
            Text(copied.wrappedValue ? "Copied — paste it into Terminal." : " ")
        }
    }

    private var addServerScreen: some View {
        VStack(spacing: 16) {
            Text("Add a server")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Enter the IP address or hostname and the port of the server you'd like to connect to.\n\nThe app supports OpenAI/MCP, LM Studio, and Ollama server endpoints.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Text("Use 127.0.0.1 for models being served locally, a LAN IP for another server on your local network, or a Tailscale IP or MagicDNS hostname for remote access from anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Text("Happy coding!")
                .font(.title3)
                .fontWeight(.semibold)
            Button("Add a server") { finishAndAddServer() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Navigation

    /// Skip (every screen but the last), Back, and Next/Done; Next on the install screen is disabled until OpenCode is found, Skip is the way around it.
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if screen != .addServer {
                Button("Skip") { finish() }
            }
            Spacer()
            switch screen {
            case .welcome:
                Button("Next") { screen = .installOpenCode }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .installOpenCode:
                Button("Back") { screen = .welcome }
                Button("Next") { screen = .addServer }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(opencodeVersion == nil)
            case .addServer:
                Button("Back") { screen = .installOpenCode }
                Button("Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
        onFinish()
    }

    private func finishAndAddServer() {
        UserDefaults.standard.set(true, forKey: Self.setupCompleteKey)
        onAddServer()
    }
}

#Preview {
    FirstRunView { }
}
