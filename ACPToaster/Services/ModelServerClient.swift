import Foundation

/// Talks to a local model server. It probes each server's native model-list
/// endpoint first (LM Studio, then Ollama) because those carry rich specs,
/// and falls back to the OpenAI-compatible `/models` shape that every server
/// also speaks.
struct ModelServerClient {
    /// What kind of server answered, so the UI can label it.
    enum ServerKind: String {
        case lmStudio = "LM Studio"
        case ollama = "Ollama"
        case openAICompatible = "OpenAI-compatible"
    }

    /// A capability a model reports it has.
    enum Capability: String, CaseIterable, Hashable {
        case vision = "vision"
        case toolUse = "tool use"
        case reasoning = "reasoning"
    }

    /// A single model as reported by the server. Spec fields are nil when the
    /// server's endpoint doesn't report them (e.g. the OpenAI fallback).
    struct ModelInfo: Identifiable, Hashable {
        /// The exact model ID to use in API calls.
        let id: String
        /// The optional "name" field, when the server provides one.
        let displayName: String?
        /// The model type, e.g. "llm" or "embedding" (LM Studio only).
        let type: String?
        /// Parameter count, e.g. "27B".
        let params: String?
        /// Quantization, e.g. "Q4_K_M".
        let quantization: String?
        /// Weight format, e.g. "gguf" or "mlx".
        let format: String?
        /// Size on disk / in memory, in bytes.
        let sizeBytes: Int64?
        /// Maximum context length, in tokens.
        let maxContextLength: Int?
        /// Capabilities the server reports for this model.
        let capabilities: Set<Capability>

        /// True for embedding (and similar utility) models that can't drive
        /// an ACP agent — they don't do chat completions.
        var isEmbedding: Bool {
            type == "embedding" || id.lowercased().contains("embedding")
        }
    }

    /// Everything a detection run tells us about a server.
    struct ModelList: Equatable {
        let models: [ModelInfo]
        let kind: ServerKind
        let latency: Duration
    }

    /// User-facing failures, with friendly descriptions. Transport failures
    /// carry the underlying system message so the real cause is visible.
    enum ServerError: LocalizedError {
        /// Connection refused, no route, or DNS failure — usually the machine is asleep or off.
        case unreachable(detail: String)
        /// The server didn't answer within the timeout.
        case timedOut
        /// The server answered, but with a non-2xx status.
        case httpError(status: Int)
        /// The response wasn't JSON in the OpenAI models shape.
        case badResponse(detail: String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let detail):
                "Can't reach this server — the machine may be asleep or off. (\(detail))"
            case .timedOut:
                "The server didn't respond in time."
            case .httpError(let status):
                "The server replied with an error (HTTP \(status))."
            case .badResponse(let detail):
                "The server's response wasn't a valid model list. (\(detail))"
            }
        }
    }

    /// How long to wait for the server to answer.
    private static let timeout: TimeInterval = 5

    /// GETs the model list, trying each native endpoint before the OpenAI
    /// fallback, and reports the models, the server kind, and the round-trip
    /// time.
    func fetchModels(from server: Server) async throws -> ModelList {
        let start = ContinuousClock.now
        let origin = Self.origin(of: server.baseURL)

        // 1. LM Studio's native v1 API carries the richest model metadata.
        if let data = try? await get(origin.appendingPathComponent("api/v1/models"), apiKey: server.apiKey),
           let models = try? Self.decodeLMStudio(data) {
            return ModelList(models: models, kind: .lmStudio, latency: ContinuousClock.now - start)
        }
        // 2. Ollama's native tags endpoint.
        if let data = try? await get(origin.appendingPathComponent("api/tags"), apiKey: server.apiKey),
           let models = try? Self.decodeOllama(data) {
            return ModelList(models: models, kind: .ollama, latency: ContinuousClock.now - start)
        }
        // 3. The OpenAI-compatible shape every server also speaks. The error
        //    from this call is the one that surfaces if the server is down.
        let data = try await get(server.baseURL.appendingPathComponent("models"), apiKey: server.apiKey)
        let models = try Self.decodeOpenAI(data)
        return ModelList(models: models, kind: .openAICompatible, latency: ContinuousClock.now - start)
    }

    /// A plain GET that throws ServerError on transport or HTTP failures.
    /// Sends `Authorization: Bearer <key>` when the server has a key.
    private func get(_ url: URL, apiKey: String?) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw Self.serverError(from: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ServerError.badResponse(detail: "the response wasn't HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServerError.httpError(status: http.statusCode)
        }
        return data
    }

    /// The scheme + host + port of a base URL, dropping any path such as `/v1`.
    private static func origin(of url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }

    /// Maps a URLError to the friendlier ServerError cases, keeping the
    /// underlying system message so the real cause shows in the UI.
    private static func serverError(from error: URLError) -> ServerError {
        switch error.code {
        case .timedOut:
            return .timedOut
        default:
            // Any other transport failure is a reachability problem for our purposes.
            return .unreachable(detail: error.localizedDescription)
        }
    }

    // MARK: - Decoding

    /// LM Studio's native v1 model list:
    /// `{"data": [{"key": ..., "display_name": ..., "params_string": ..., ...}]}`.
    private static func decodeLMStudio(_ data: Data) throws -> [ModelInfo] {
        struct Quantization: Decodable {
            let name: String?
        }
        struct Reasoning: Decodable {
            let allowed_options: [String]?
        }
        struct Capabilities: Decodable {
            let vision: Bool?
            let trained_for_tool_use: Bool?
            let reasoning: Reasoning?
        }
        struct Entry: Decodable {
            let key: String
            let type: String?
            let display_name: String?
            let params_string: String?
            let quantization: Quantization?
            let format: String?
            let size_bytes: Int64?
            let max_context_length: Int?
            let capabilities: Capabilities?
        }
        // The docs call this array "data"; the live server sends "models".
        // Accept either so a rename in either direction doesn't break us.
        struct Payload: Decodable {
            let models: [Entry]?
            let data: [Entry]?
            var entries: [Entry] { models ?? data ?? [] }
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.entries
            .filter { !$0.key.isEmpty }
            .map { entry in
                var caps: Set<Capability> = []
                if entry.capabilities?.vision == true { caps.insert(.vision) }
                if entry.capabilities?.trained_for_tool_use == true { caps.insert(.toolUse) }
                if let options = entry.capabilities?.reasoning?.allowed_options, !options.isEmpty {
                    caps.insert(.reasoning)
                }
                return ModelInfo(
                    id: entry.key,
                    displayName: entry.display_name,
                    type: entry.type,
                    params: entry.params_string,
                    quantization: entry.quantization?.name,
                    format: entry.format,
                    sizeBytes: entry.size_bytes,
                    maxContextLength: entry.max_context_length,
                    capabilities: caps
                )
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Ollama's tags endpoint:
    /// `{"models": [{"name": ..., "size": ..., "details": {...}}]}`.
    private static func decodeOllama(_ data: Data) throws -> [ModelInfo] {
        struct Details: Decodable {
            let format: String?
            let parameter_size: String?
            let quantization_level: String?
        }
        struct Entry: Decodable {
            let name: String
            let size: Int64?
            let details: Details?
        }
        struct Payload: Decodable {
            let models: [Entry]
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.models
            .filter { !$0.name.isEmpty }
            .map { entry in
                ModelInfo(
                    id: entry.name,
                    displayName: nil,
                    type: nil,
                    params: entry.details?.parameter_size,
                    quantization: entry.details?.quantization_level,
                    format: entry.details?.format,
                    sizeBytes: entry.size,
                    maxContextLength: nil,
                    capabilities: []
                )
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// The OpenAI models response shape: `{"data": [{"id": ..., "name": ...}]}`.
    private static func decodeOpenAI(_ data: Data) throws -> [ModelInfo] {
        struct Entry: Decodable {
            let id: String
            let name: String?
        }
        struct Payload: Decodable {
            let data: [Entry]
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.data
            .filter { !$0.id.isEmpty }
            .map { entry in
                ModelInfo(
                    id: entry.id,
                    displayName: entry.name,
                    type: nil,
                    params: nil,
                    quantization: nil,
                    format: nil,
                    sizeBytes: nil,
                    maxContextLength: nil,
                    capabilities: []
                )
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
