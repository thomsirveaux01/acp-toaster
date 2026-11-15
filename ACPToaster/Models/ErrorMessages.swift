import Foundation

/// Every user-facing error and failure message in the app, gathered in one
/// place so the wording is easy to review and tweak. Messages that don't
/// interpolate anything are properties; messages that take a value are
/// functions. Each is grouped by the area it belongs to.
enum ErrorMessages {

    // MARK: - Reaching a server (ModelServerClient.ServerError)

    /// The server couldn't be reached at all — off, asleep, or wrong address.
    static func unreachable(detail: String) -> String {
        "Can't reach this server — the machine may be asleep or off. (\(detail))"
    }

    /// The server didn't answer within the timeout.
    static var timedOut: String {
        "The server didn't respond in time."
    }

    /// The server answered, but with a non-2xx status.
    static func httpError(status: Int) -> String {
        "The server replied with an error (HTTP \(status))."
    }

    /// The server's response wasn't a valid model list.
    static func badResponse(detail: String) -> String {
        "The server's response wasn't a valid model list. (\(detail))"
    }

    // MARK: - OpenCode config (OpenCodeConfigStore.ConfigError)

    /// The config file couldn't be read.
    static var configUnreadable: String {
        "Couldn't read the OpenCode config file."
    }

    /// The config file isn't valid JSON, so it was left unchanged.
    static var configInvalidJSON: String {
        "The OpenCode config file isn't valid JSON, so it was left unchanged."
    }

    /// The config file couldn't be written.
    static var configWriteFailed: String {
        "Couldn't write the OpenCode config file."
    }

    // MARK: - Server list (AppModel)

    /// The server name is empty.
    static var serverNameRequired: String {
        "Give the server a name."
    }

    /// The address didn't normalize into a valid host:port.
    static var serverAddressInvalid: String {
        "That address doesn't look right. Use host and port, like 127.0.0.1:1235."
    }

    /// Another server already uses that address.
    static func serverDuplicate(hostPort: String) -> String {
        "A server at \(hostPort) is already in your list."
    }

    /// The server being edited is no longer in the list.
    static var serverMissing: String {
        "That server is no longer in your list."
    }

    // MARK: - Toasting / wrappers (ServerDetailView)

    /// The wrapper script couldn't be deleted.
    static func deleteWrapperFailed(detail: String) -> String {
        "Couldn't delete wrapper: \(detail)"
    }

    // MARK: - Settings (SettingsView)

    /// `brew install opencode` exited non-zero.
    static func opencodeInstallFailed(status: Int32) -> String {
        "Install failed (exit status \(status))."
    }

    // MARK: - Expert skill (ExpertSkillInstaller)

    /// The Xcode expert skill couldn't be installed.
    static func expertSkillFailed(detail: String) -> String {
        "Couldn't install the Xcode expert skill: \(detail)"
    }

    // MARK: - Homebrew (BrewService)

    /// The brew process couldn't be started (surfaced in the install log).
    static func brewStartFailed(detail: String) -> String {
        "Failed to start brew: \(detail)"
    }
}
