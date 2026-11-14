import SwiftUI
import AppKit

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 720, height: 520)
        .commands {
            // The standard About panel (icon, name, version) with a credits
            // block underneath, including a clickable GitHub link.
            CommandGroup(replacing: .appInfo) {
                Button("About ACP Toaster") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
                }
            }
        }
    }

    /// The credits block shown in the standard About panel.
    private static let credits: NSAttributedString = {
        let base = NSMutableAttributedString(
            string: "Andrew Cunningham, 2026\n\nVibe-coded locally with open-weight Apache 2.0 models on Apple Silicon Macs\n\nGitHub: "
        )
        let link = NSAttributedString(
            string: "https://github.com/thomsirveaux01/acp-toaster",
            attributes: [.link: "https://github.com/thomsirveaux01/acp-toaster"]
        )
        base.append(link)
        return base
    }()
}
