import Foundation

/// Detects an existing OpenCode installation on this machine.
struct OpencodeLocator {
    enum Detection {
        case found(path: String, version: String?)
        case notFound
    }

    /// Directories checked before falling back to the user's shell PATH.
    private static let knownPaths: [String] = [
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
        NSHomeDirectory() + "/.opencode/bin/opencode",
        NSHomeDirectory() + "/.local/bin/opencode",
    ]

    /// Finds an OpenCode binary, if one is installed.
    func detect() async -> Detection {
        for path in Self.knownPaths where isExecutable(path) {
            return .found(path: path, version: await Self.version(at: path))
        }
        // Pick up PATH additions from the user's shell profile.
        if let path = await Self.shellLookup(), isExecutable(path) {
            return .found(path: path, version: await Self.version(at: path))
        }
        return .notFound
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
