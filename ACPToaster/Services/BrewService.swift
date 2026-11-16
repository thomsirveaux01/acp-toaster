import Foundation

struct BrewService {
    /// The one-liner that installs Homebrew itself. Copied to the clipboard, never run: it needs sudo, which a GUI app shouldn't prompt for.
    static let installerCommand =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    static let opencodeInstallCommand = "brew install opencode"

    static func brewPath() -> String? {
        for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    final class Install {
        /// Combined stdout+stderr, one element per line.
        let lines: AsyncStream<String>

        /// The brew process's exit status; valid once `lines` is exhausted.
        var exitStatus: Int32 { status.value }

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
            if termination == .cancelled {
                process.terminate()
            }
        }

        do {
            try process.run()
        } catch {
            continuation.yield("Failed to start brew: \(error.localizedDescription)")
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

    fileprivate final class ExitStatusBox: @unchecked Sendable {
        // Written by the pump task, read on the main actor after the stream ends.
        nonisolated(unsafe) var value: Int32 = -1
    }
}
