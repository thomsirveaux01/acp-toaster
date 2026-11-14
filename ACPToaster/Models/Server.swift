import Foundation

/// A local OpenAI-compatible model server (LM Studio, Bionic, …).
struct Server: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Always normalized: includes the scheme and ends with `/v1`.
    var baseURL: URL

    init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    /// `host:port`, for display.
    var hostPort: String {
        guard let host = baseURL.host else { return "" }
        guard let port = baseURL.port else { return host }
        return "\(host):\(port)"
    }

    /// Normalizes a user-entered address into a full `http://host:port/v1` URL.
    ///
    /// Accepts `127.0.0.1:1235`, `http://127.0.0.1:1235`,
    /// `http://127.0.0.1:1235/v1`, or a LAN/Tailscale address. Returns nil when
    /// the input has no host or isn't a valid URL.
    static func normalizedBaseURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        // Drop trailing slashes; a clean `/v1` path is appended below.
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        components.path = components.path.hasSuffix("/v1") ? components.path : "/v1"
        return components.url
    }
}
