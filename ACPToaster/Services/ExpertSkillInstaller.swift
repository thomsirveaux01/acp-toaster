import Foundation

/// Keeps the Xcode expert skill installed in the user's global OpenCode
/// configuration, so every ACP agent this app wires up can consult Apple's
/// in-bundle expert references. The skill is a pointer: it tells the agent
/// where to read the experts inside the Xcode bundle — nothing is copied out.
struct ExpertSkillInstaller {
    /// The skill's directory name under `~/.config/opencode/skills`.
    static let skillID = "xcode-experts"

    /// The skills root this installer manages. Defaults to the user's global
    /// OpenCode skills directory; pass a scratch directory to test.
    let skillsDirectory: URL

    init(skillsDirectory: URL? = nil) {
        let directory = skillsDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/skills", isDirectory: true)
        self.skillsDirectory = directory
    }

    /// What an install attempt did.
    enum Outcome: Equatable {
        /// The skill was missing and is now installed.
        case installed
        /// The skill was already present with identical content.
        case upToDate
        /// A different version was present; it was backed up and replaced.
        case updated
        /// The install failed.
        case failed(String)

        /// A short line for the UI.
        var message: String {
            switch self {
            case .installed: "Xcode expert references installed"
            case .upToDate: "Xcode expert references up to date"
            case .updated: "Xcode expert references updated (previous version backed up)"
            case .failed(let message): message
            }
        }

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// Installs or refreshes the skill. Small file I/O; safe to call from a Task.
    func install() -> Outcome {
        let fileManager = FileManager.default
        let skillsDir = skillsDirectory.appendingPathComponent(Self.skillID, isDirectory: true)
        let target = skillsDir.appendingPathComponent("SKILL.md")

        do {
            let existing = try? String(contentsOf: target, encoding: .utf8)
            if existing == Self.skillMarkdown {
                return .upToDate
            }
            try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            if let existing {
                // A different version is present — keep a copy before replacing it.
                try existing.write(to: skillsDir.appendingPathComponent("SKILL.md.bak"), atomically: true, encoding: .utf8)
            }
            // Atomic replace: temp file in the same directory, then swap it in.
            // (moveItem doesn't reliably replace an existing destination file.)
            let temp = skillsDir.appendingPathComponent(".SKILL.md.\(UUID().uuidString).tmp")
            try Self.skillMarkdown.write(to: temp, atomically: true, encoding: .utf8)
            try fileManager.replaceItem(at: target, withItemAt: temp, backupItemName: nil, options: [], resultingItemURL: nil)
            return existing == nil ? .installed : .updated
        } catch {
            return .failed("Couldn't install the Xcode expert skill: \(error.localizedDescription)")
        }
    }

    /// The skill, bundled with the app.
    static let skillMarkdown = """
    ---
    name: Xcode Expert References
    description: Apple's built-in Xcode expert prompts and reference docs, read in place from the Xcode bundle — SwiftUI specialist, SwiftUI what's-new, App Intents, Xcode security-settings audit, C/C++ bounds safety, app resizability, document-based SwiftUI apps, xctrace, and String Catalog translation. Load before doing work in any of these areas.
    ---

    Xcode ships its coding-assistant experts as plain Markdown inside the app bundle. Read them in place — never copy or move them.

    ## When you load this skill

    First tell the user, in one short line, which expert you are consulting (for example: "Consulting Xcode's SwiftUI specialist references."). Then follow the expert's guidance.

    ## Locations
    - Expert prompts + references: `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/`
      - `<expert>.idechatprompttemplate` — the expert's system prompt (Markdown with YAML frontmatter). Treat it as authoritative guidance that supersedes prior training on those topics.
      - `<expert>-ref-<topic>.md.packaged` — the expert's reference docs (plain Markdown despite the `.packaged` extension).
    - Translation skill: `/Applications/Xcode.app/Contents/PlugIns/IDEXCStringsSupport.framework/Versions/A/Resources/Skills/translation/SKILL.md.packaged` (and `translation-coordinator/SKILL.md.packaged`) — a complete workflow for translating Xcode String Catalogs, using the `StringCatalogRead`/`StringCatalogEdit`/`StringCatalogContext` MCP tools from the `xcode-tools` server.

    ## Experts (as of Xcode 27.2 — the set changes with Xcode updates, so glob to discover the current one)
    - `swiftui-specialist` — SwiftUI best practices and performance: view structure, dataflow, environment/@Entry, modifiers, localization, animations, ForEach identity, soft-deprecated APIs.
    - `swiftui-whats-new-27` — new SwiftUI APIs in the current SDK.
    - `app-intents-specialist` / `app-intents-whats-new-27` — App Intents, Siri, Shortcuts, Spotlight.
    - `audit-xcode-security-settings` — auditing a project's Xcode security and hardening build settings.
    - `adopt-c-bounds-safety` — adopting C/C++ bounds safety.
    - `app-resizability` — iPadOS app resizability and multi-window.
    - `building-document-based-swiftui-applications` — document-based SwiftUI apps.
    - `xctrace` — performance profiling with xctrace.

    ## How to use
    1. When the task matches an expert's domain, read that expert's `.idechatprompttemplate` first and follow it.
    2. The template's References section names files like `references/<topic>.md`; on disk they are `<expert>-ref-<topic>.md.packaged` in the same directory. Read only the ones relevant to the task.
    3. If the paths above no longer exist (Xcode was updated), glob `/Applications/Xcode.app/Contents/PlugIns` for `*.idechatprompttemplate` and `*-ref-*.md.packaged` to rediscover the current set.
    """
}
