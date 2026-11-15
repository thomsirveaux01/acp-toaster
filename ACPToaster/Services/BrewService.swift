import Foundation

/// Installs OpenCode via Homebrew, streaming live output.
struct BrewService {
    /// The Homebrew executable, if present.
    static func brewPath() -> String? {
        for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    /// Homebrew's version (e.g. "4.3.21"), or nil when brew isn't installed.
    static func brewVersion() async -> String? {
        guard let brew = brewPath() else { return nil }
        let (status, stdout) = await run(brew, ["--version"])
        guard status == 0 else { return nil }
        // The first line is "Homebrew 4.3.21"; the version is its last token.
        guard let firstLine = stdout.split(whereSeparator: \.isNewline).first else { return nil }
        return firstLine.split(separator: " ").last.map(String.init)
    }

    /// A running (or finished) `brew install opencode` process.
    final class Install {
        /// Combined stdout+stderr, one element per line.
        let lines: AsyncStream<String>

        /// The brew process's exit status; valid once `lines` is exhausted.
        var exitStatus: Int32 { status.value }

        /// Terminates the child process if it is still running.
        func cancel() {
            if process.isRunning {
                process.terminate()
            }
        }

        private let process: Process
        private let status: ExitStatusBox

        fileprivate init(process: Process, status: ExitStatusBox, lines: AsyncStream<String>) {
            self.process = process
            self.status = status
            self.lines = lines
        }
    }

    /// Starts `brew install opencode` and streams its combined output line by line.
    func install() -> Install {
        let process = Process()
        let brew = Self.brewPath() ?? "/opt/homebrew/bin/brew"
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "opencode"]
        // GUI apps get a minimal environment; give brew what it needs.
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "\(Self.brewDir(for: brew)):/usr/bin:/bin",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let status = ExitStatusBox()
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        continuation.onTermination = { termination in
            // The consumer went away (e.g. its task was cancelled): stop the child.
            if termination == .cancelled {
                process.terminate()
            }
        }

        do {
            try process.run()
        } catch {
            continuation.yield(ErrorMessages.brewStartFailed(detail: error.localizedDescription))
            continuation.finish()
            return Install(process: process, status: status, lines: stream)
        }

        // Pump the pipe off the main actor so the UI stays responsive.
        let fileHandle = pipe.fileHandleForReading
        Task.detached {
            Self.pump(fileHandle, continuation)
            process.waitUntilExit()
            status.value = process.terminationStatus
            continuation.finish()
        }

        return Install(process: process, status: status, lines: stream)
    }

    private static func brewDir(for brew: String) -> String {
        (brew as NSString).deletingLastPathComponent
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
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Reads the pipe to EOF, yielding one stream element per complete line.
    nonisolated private static func pump(_ fileHandle: FileHandle, _ continuation: AsyncStream<String>.Continuation) {
        var buffer = Data()
        while true {
            let chunk = fileHandle.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8) ?? ""
                buffer.removeSubrange(buffer.startIndex...newline)
                continuation.yield(line)
            }
        }
        // Flush a trailing line that had no newline.
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            continuation.yield(line)
        }
    }

    /// Shared holder for the child process's exit status, written by the pump task.
    fileprivate final class ExitStatusBox: @unchecked Sendable {
        // Written by the pump task, read on the main actor after the stream ends.
        nonisolated(unsafe) var value: Int32 = -1
    }
}
