import Foundation

/// Detects an existing OpenCode installation on this machine.
struct OpencodeLocator {
    enum Detection {
        case found(path: String, version: String?)
        case notFound
    }

    /// Directories checked before falling back to npm's global root and the
    /// user's shell PATH: Homebrew (both prefixes), the official curl
    /// installer (~/.opencode/bin, where opencode.ai/v2/install puts it),
    /// and the generic user bin.
    private static let knownPaths: [String] = [
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
        NSHomeDirectory() + "/.opencode/bin/opencode",
        NSHomeDirectory() + "/.local/bin/opencode",
    ]

    /// Finds an OpenCode binary, if one is installed — via Homebrew, npm,
    /// the official curl installer, or anywhere else on the shell PATH.
    func detect() async -> Detection {
        for path in Self.knownPaths where isExecutable(path) {
            return .found(path: path, version: await Self.version(at: path))
        }
        // An npm global install lives under npm's global prefix, which may
        // not be on PATH (nvm, volta, fnm, …).
        if let path = await Self.npmGlobalLookup(), isExecutable(path) {
            return .found(path: path, version: await Self.version(at: path))
        }
        // Pick up PATH additions from the user's shell profile.
        if let path = await Self.shellLookup(), isExecutable(path) {
            return .found(path: path, version: await Self.version(at: path))
        }
        return .notFound
    }

    /// Asks the user's login shell where npm's global root is, so an
    /// npm-installed OpenCode is found even when its bin dir isn't on PATH.
    /// Nil when npm itself isn't installed.
    nonisolated private static func npmGlobalLookup() async -> String? {
        let (status, stdout) = await run("/bin/zsh", ["-lc", "npm prefix -g 2>/dev/null"])
        guard status == 0 else { return nil }
        let prefix = stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let prefix, !prefix.isEmpty else { return nil }
        return prefix + "/bin/opencode"
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// Asks the user's login shell where `opencode` lives.
    nonisolated private static func shellLookup() async -> String? {
        let (status, stdout) = await run("/bin/zsh", ["-lc", "command -v opencode"])
        guard status == 0 else { return nil }
        let line = stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    /// Runs `<path> --version` and returns the first non-empty stdout line.
    nonisolated private static func version(at path: String) async -> String? {
        let (status, stdout) = await run(path, ["--version"])
        guard status == 0 else { return nil }
        return stdout
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Runs a process and captures its exit status and stdout.
    /// Nonisolated so the blocking read happens off the main actor.
    nonisolated private static func run(_ launchPath: String, _ arguments: [String]) async -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // keep stderr out of the captured output
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
