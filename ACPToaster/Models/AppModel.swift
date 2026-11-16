import Foundation
import Observation

struct AppModelError: LocalizedError, Hashable {
    let message: String

    var errorDescription: String? { message }
}

@Observable
final class AppModel {
    static let serversKey = "acptoaster.servers"

    struct ModelSelection: Codable, Hashable, Identifiable {
        var serverID: UUID
        /// The exact model ID the server reports.
        var modelID: String
        var displayName: String?

        var id: String { "\(serverID.uuidString)/\(modelID)" }
    }

    var servers: [Server] {
        didSet { saveServers() }
    }

    /// Intentionally not persisted.
    var selections: [ModelSelection] = []

    init() {
        servers = Self.loadServers()
    }

    // MARK: - Intents

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

    private static func normalizedKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func removeServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        selections.removeAll { $0.serverID == id }
    }

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
