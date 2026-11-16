import Foundation

/// Writes the per-model ACP wrapper scripts Xcode launches in place of raw `opencode acp`: they fix Xcode's sanitized environment, pin the model in the OpenCode config, and exec the real binary.
struct WrapperGenerator {
    struct Result: Identifiable {
        let selection: AppModel.ModelSelection
        /// Absolute path to the wrapper script, for pasting into Xcode.
        let wrapperPath: String
        /// True when the script didn't exist before this run.
        let created: Bool
        let error: String?

        var id: String { selection.id }
    }

    /// Lowercases and collapses non-alphanumerics into single `-`: "qwen3.8-27b" → "qwen3-8-27b".
    static func slug(_ text: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                pendingSeparator = false
            } else if !pendingSeparator {
                slug.append("-")
                pendingSeparator = true
            }
        }
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    /// The provider ID shared by the OpenCode config entry and the wrapper's
    /// model pin, so the two always agree.
    static func providerID(for server: Server) -> String {
        let slug = slug(server.name)
        return slug.isEmpty ? "server" : slug
    }

    /// The deterministic wrapper path for one (server, model) pair; used to write the wrapper and to restore toasted models from disk.
    static func wrapperPath(for selection: AppModel.ModelSelection, server: Server, homeDir: String) -> String {
        let providerID = Self.providerID(for: server)
        let fileName = "opencode-acp-\(providerID)-\(Self.slug(selection.modelID)).sh"
        let binDir = (homeDir as NSString).appendingPathComponent("bin")
        return (binDir as NSString).appendingPathComponent(fileName)
    }

    func generate(for selection: AppModel.ModelSelection, server: Server, opencodePath: String, homeDir: String) -> Result {
        let providerID = Self.providerID(for: server)
        let wrapperPath = Self.wrapperPath(for: selection, server: server, homeDir: homeDir)
        let fileName = (wrapperPath as NSString).lastPathComponent
        let binDir = (homeDir as NSString).appendingPathComponent("bin")

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: binDir, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binDir)

            let existed = fileManager.fileExists(atPath: wrapperPath)
            let script = Self.script(serverName: server.name, providerID: providerID, modelID: selection.modelID, opencodePath: opencodePath, homeDir: homeDir, scriptName: fileName)
            try script.write(toFile: wrapperPath, atomically: true, encoding: .utf8)
            // The atomic write replaces the inode, so re-assert the mode.
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath)

            return Result(selection: selection, wrapperPath: wrapperPath, created: !existed, error: nil)
        } catch {
            return Result(selection: selection, wrapperPath: wrapperPath, created: false, error: error.localizedDescription)
        }
    }

    /// The wrapper script body. Matches the proven BSD/macOS sed template;
    /// the pin pattern matches ANY current value of "model".
    private static func script(serverName: String, providerID: String, modelID: String, opencodePath: String, homeDir: String, scriptName: String) -> String {
        let pin = "\(providerID)/\(modelID)"
        let escapedPin = sedEscape(pin)
        return """
        #!/bin/sh
        # ACP wrapper for Xcode -> OpenCode -> \(serverName)
        # Pins model: \(pin)
        LOG=/tmp/acp-wrapper.log
        {
          echo "--- $(date) \(scriptName) ---"
          echo "HOME=$HOME"
          echo "PATH=$PATH"
        } >> "$LOG" 2>&1

        export HOME=\(homeDir)
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        CFG="$HOME/.config/opencode/opencode.json"
        if [ -f "$CFG" ]; then
          sed -i '' 's/"model"[[:space:]]*:[[:space:]]*"[^"]*"/"model": "\(escapedPin)"/' "$CFG"
        fi

        exec "\(opencodePath)" acp "$@"
        """
    }

    /// Escapes `\`, `&`, and `/` for a sed replacement string.
    private static func sedEscape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "&" || character == "/" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
