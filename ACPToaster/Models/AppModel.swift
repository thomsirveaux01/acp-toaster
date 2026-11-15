import Foundation
import Observation

/// A user-facing failure from an AppModel intent.
struct AppModelError: LocalizedError, Hashable {
    let message: String

    var errorDescription: String? { message }
}

/// Shared app state: the configured model servers and the models picked from them.
@Observable
final class AppModel {
    /// UserDefaults key for the persisted server list.
    static let serversKey = "acptoaster.servers"

    /// A model chosen from a server, ready to be wrapped in Phase 3.
    struct ModelSelection: Codable, Hashable, Identifiable {
        var serverID: UUID
        /// The exact model ID the server reports.
        var modelID: String
        /// The server's optional display name for the model, if any.
        var displayName: String?

        var id: String { "\(serverID.uuidString)/\(modelID)" }
    }

    /// Configured servers, persisted to UserDefaults.
    var servers: [Server] {
        didSet { saveServers() }
    }

    /// Models the user picked; intentionally not persisted.
    var selections: [ModelSelection] = []

    init() {
        servers = Self.loadServers()
    }

    // MARK: - Intents

    /// Validates and adds a server. Fails with a user-facing message when the
    /// name is empty, the address doesn't normalize, or the server already exists.
    @discardableResult
    func addServer(name: String, address: String, icon: String, apiKey: String) -> Result<Server, AppModelError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(AppModelError(message: "Give the server a name."))
        }
        guard let baseURL = Server.normalizedBaseURL(from: address) else {
            return .failure(AppModelError(message: "Use valid hostname or port, like 127.0.0.1:1235."))
        }
        if servers.contains(where: { $0.baseURL == baseURL }) {
            let hostPort = baseURL.port.map { "\(baseURL.host ?? ""):\($0)" } ?? (baseURL.host ?? "")
            return .failure(AppModelError(message: "A server at \(hostPort) is already in your list."))
        }
        let server = Server(name: trimmedName, baseURL: baseURL, icon: icon, apiKey: Self.normalizedKey(apiKey))
        servers.append(server)
        return .success(server)
    }

    /// Updates a server's name, address, and API key. Fails with a user-facing
    /// message when the name is empty, the address doesn't normalize, or
    /// another server already uses that address.
    @discardableResult
    func updateServer(_ id: UUID, name: String, address: String, icon: String, apiKey: String) -> Result<Server, AppModelError> {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return .failure(AppModelError(message: "That server is no longer in your list."))
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(AppModelError(message: "Give the server a name."))
        }
        guard let baseURL = Server.normalizedBaseURL(from: address) else {
            return .failure(AppModelError(message: "Use valid hostname or port, like 127.0.0.1:1235."))
        }
        if servers.contains(where: { $0.id != id && $0.baseURL == baseURL }) {
            let hostPort = baseURL.port.map { "\(baseURL.host ?? ""):\($0)" } ?? (baseURL.host ?? "")
            return .failure(AppModelError(message: "A server at \(hostPort) is already in your list."))
        }
        servers[index].name = trimmedName
        servers[index].baseURL = baseURL
        servers[index].icon = icon
        servers[index].apiKey = Self.normalizedKey(apiKey)
        return .success(servers[index])
    }

    /// Trims the key and treats an empty one as "no auth".
    private static func normalizedKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Removes a server and any selections that referenced it.
    func removeServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        selections.removeAll { $0.serverID == id }
    }

    /// Adds the selection if absent, removes it if present.
    func toggleSelection(_ selection: ModelSelection) {
        if let index = selections.firstIndex(of: selection) {
            selections.remove(at: index)
        } else {
            selections.append(selection)
        }
    }

    // MARK: - Persistence

    private static func loadServers() -> [Server] {
        guard let data = UserDefaults.standard.data(forKey: serversKey) else { return [] }
        return (try? JSONDecoder().decode([Server].self, from: data)) ?? []
    }

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: Self.serversKey)
    }
}
