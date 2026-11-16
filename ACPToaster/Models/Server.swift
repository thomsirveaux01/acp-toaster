import Foundation

/// The SF Symbols a server can wear (outline glyphs only).
enum ServerIcon: String, CaseIterable, Identifiable {
    case macDesktop = "desktopcomputer"
    case macPro = "macpro.gen3"
    case macStudio = "macstudio"
    case macMini = "macmini"
    case macMiniGen2 = "macmini.gen2"
    case macLaptop = "macbook"
    case laptop = "laptopcomputer"
    case pc = "pc"
    case serverRack = "server.rack"
    case cpu = "cpu"
    case cloud = "cloud"

    var id: String { rawValue }
    var symbol: String { rawValue }
    var label: String {
        switch self {
        case .macDesktop: "iMac"
        case .macPro: "Mac Pro"
        case .macStudio: "Mac Studio"
        case .macMini: "Mac mini (M4/M6)"
        case .macMiniGen2: "Mac mini (M1/M2)"
        case .macLaptop: "MacBook"
        case .laptop: "Laptop"
        case .pc: "PC"
        case .serverRack: "Server Rack"
        case .cpu: "CPU"
        case .cloud: "Cloud"
        }
    }
}

struct Server: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Always normalized: includes the scheme and ends with `/v1`.
    var baseURL: URL
    var icon: String
    /// Optional API key; nil means no `Authorization` header is sent and no key is written to the config.
    var apiKey: String?

    init(id: UUID = UUID(), name: String, baseURL: URL, icon: String = ServerIcon.macDesktop.symbol, apiKey: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.icon = icon
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, icon, apiKey
    }

    /// Decodes a server; ones saved before icons or keys existed get the
    /// defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ServerIcon.macDesktop.symbol
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
    }

    var hostPort: String {
        guard let host = baseURL.host else { return "" }
        guard let port = baseURL.port else { return host }
        return "\(host):\(port)"
    }

    /// Normalizes a user-entered address (`127.0.0.1:1235`, with or without scheme or `/v1`) into a full `http://host:port/v1` URL.
    static func normalizedBaseURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
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
