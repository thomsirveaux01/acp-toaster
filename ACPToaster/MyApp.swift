import SwiftUI
import AppKit

@main struct MyApp: App {
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(updater: updater)
        }
        .defaultSize(width: 720, height: 520)
        .commands {
            // The standard About panel (icon, name, version) with a credits
            // block underneath, including a clickable GitHub link.
            CommandGroup(replacing: .appInfo) {
                Button("About ACP Toaster") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
                }
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
            }
        }
        // Settings is a sheet on the main window (toolbar gear / ⌘,), not a
        // separate Settings scene, so it stays attached to the app.
    }

    /// The credits block shown in the standard About panel, styled like
    /// Running the Table's: centered small-system text with a little extra
    /// line spacing, and the word "GitHub" itself as the link.
    private static let credits: NSAttributedString = {
        let text = "Andrew Cunningham, 2026\n\nVibe-coded locally with open-weight Apache 2.0 models on Apple Silicon Macs\n\nGitHub"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // Extra line space between the wrapped lines of the credits paragraph.
        paragraph.lineSpacing = 2.0
        let credits = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph,
        ])
        if let url = URL(string: "https://github.com/thomsirveaux01/acp-toaster") {
            let range = (text as NSString).range(of: "GitHub")
            credits.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: range)
        }
        return credits
    }()
}
