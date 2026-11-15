import Foundation

/// Every user-facing message in the app — errors, successes, and status
/// lines — gathered in one place so the wording is easy to review and tweak.
/// Messages that don't interpolate anything are properties; messages that
/// take a value are functions. Each is grouped by the area it belongs to.
enum UserMessages {

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

    // MARK: - Detection status (ServerDetailView)

    /// The kind of server that answered, above the status line.
    static func serverType(kind: String) -> String {
        "Server type: \(kind)"
    }

    /// A detection run is in flight.
    static var detecting: String {
        "Detecting…"
    }

    /// The server has never been checked in this session.
    static var notCheckedYet: String {
        "Not checked yet"
    }

    /// The server is up: how many models it offers and how long the ping took.
    static func modelsUp(count: Int, latency: String) -> String {
        "\(count) models · \(latency)"
    }

    // MARK: - Toasting / wrappers (ServerDetailView)

    /// A toast run is in flight for one model.
    static func toasting(name: String) -> String {
        "Toasting \(name)…"
    }

    /// The toast succeeded.
    static var toasted: String {
        "Toasted!"
    }

    /// The wrapper script was deleted.
    static func deletedWrapper(path: String) -> String {
        "Deleted wrapper · \(path)"
    }

    /// The wrapper script couldn't be deleted.
    static func deleteWrapperFailed(detail: String) -> String {
        "Couldn't delete wrapper: \(detail)"
    }

    /// The status bar's idle line.
    static var ready: String {
        "Ready"
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

    // MARK: - Settings (SettingsView)

    /// A tool is installed.
    static var installed: String {
        "Installed"
    }

    /// A tool isn't installed.
    static var notInstalled: String {
        "Not installed"
    }

    /// Why the Homebrew Install button copies a command instead of running it.
    static var brewInstallCaption: String {
        "The installer needs sudo, so Install copies the command — paste it into Terminal."
    }

    /// The Homebrew installer command is on the clipboard.
    static var brewCopiedCaption: String {
        "Copied — paste it into Terminal."
    }

    /// `brew install opencode` is running.
    static var installingOpenCode: String {
        "Installing via Homebrew…"
    }

    /// OpenCode can't be installed until Homebrew is.
    static var installHomebrewFirst: String {
        "Install Homebrew first."
    }

    /// `brew install opencode` exited non-zero.
    static func opencodeInstallFailed(status: Int32) -> String {
        "Install failed (exit status \(status))."
    }

    // MARK: - Expert skill (ExpertSkillInstaller)

    /// The skill was missing and is now installed.
    static var expertSkillInstalled: String {
        "Xcode expert references installed"
    }

    /// The skill was already present with identical content.
    static var expertSkillUpToDate: String {
        "Xcode expert references up to date"
    }

    /// A different version was present; it was backed up and replaced.
    static var expertSkillUpdated: String {
        "Xcode expert references updated (previous version backed up)"
    }

    /// The skill couldn't be installed.
    static func expertSkillFailed(detail: String) -> String {
        "Couldn't install the Xcode expert skill: \(detail)"
    }

    // MARK: - Homebrew (BrewService)

    /// The brew process couldn't be started (surfaced in the install log).
    static func brewStartFailed(detail: String) -> String {
        "Failed to start brew: \(detail)"
    }
}
