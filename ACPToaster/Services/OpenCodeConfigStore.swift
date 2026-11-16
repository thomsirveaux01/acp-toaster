import Foundation

/// Manages `~/.config/opencode/opencode.json`; merges with whatever the user has, leaving unknown keys and other providers untouched.
struct OpenCodeConfigStore {
    let configURL: URL

    /// Pass a scratch directory to test.
    init(configDirectory: URL? = nil) {
        let directory = configDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/opencode", isDirectory: true)
        configURL = directory.appendingPathComponent("opencode.json")
    }

    enum ConfigError: LocalizedError {
        case unreadable
        case invalidJSON
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read OpenCode config file."
            case .invalidJSON: "OpenCode config file isn't valid JSON, so it was left unchanged."
            case .writeFailed: "Couldn't write OpenCode config file."
            }
        }
    }

    /// Merges the server's provider entry into the config; idempotent.
    func ensureProvider(server: Server, models: [AppModel.ModelSelection]) throws {
        let providerID = WrapperGenerator.providerID(for: server)
        let fileManager = FileManager.default

        let exists = fileManager.fileExists(atPath: configURL.path)
        var config: [String: Any]
        if exists {
            let data: Data
            do {
                data = try Data(contentsOf: configURL)
            } catch {
                throw ConfigError.unreadable
            }
            do {
                let parsed = try JSONSerialization.jsonObject(with: data)
                guard let object = parsed as? [String: Any] else {
                    throw ConfigError.invalidJSON
                }
                config = object
            } catch let error as ConfigError {
                throw error
            } catch {
                throw ConfigError.invalidJSON
            }
        } else {
            config = ["$schema": "https://opencode.ai/config.json"]
        }

        if let provider = config["provider"], !(provider is [String: Any]) {
            throw ConfigError.invalidJSON
        }
        var providers = (config["provider"] as? [String: Any]) ?? [:]

        var modelsDict: [String: Any] = [:]
        for model in models {
            modelsDict[model.modelID] = ["name": model.displayName ?? model.modelID]
        }
        var entry: [String: Any] = [
            "npm": "@ai-sdk/openai-compatible",
            "name": server.name,
            "options": [
                "baseURL": server.baseURL.absoluteString,
                // The real key when the server requires auth; a dummy value
                // otherwise, since the SDK wants the field to exist.
                "apiKey": server.apiKey ?? "lm-studio",
            ],
            "models": modelsDict,
        ]

        // Merge with any existing entry: union of the models map (new entries
        // win), and any extra keys the user added are preserved.
        if let existing = providers[providerID] as? [String: Any] {
            var mergedModels = existing["models"] as? [String: Any] ?? [:]
            for (id, value) in modelsDict {
                mergedModels[id] = value
            }
            entry["models"] = mergedModels
            for (key, value) in existing where entry[key] == nil {
                entry[key] = value
            }
        }
        providers[providerID] = entry
        config["provider"] = providers

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw ConfigError.writeFailed
        }

        do {
            try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if exists {
                let backupURL = configURL.appendingPathExtension("bak")
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: configURL, to: backupURL)
            }
            // Atomic write: temp file in the same directory, then rename over.
            let tempURL = configURL.deletingLastPathComponent()
                .appendingPathComponent("opencode.json.\(UUID().uuidString).tmp")
            try data.write(to: tempURL)
            try fileManager.replaceItem(at: configURL, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
        } catch {
            throw ConfigError.writeFailed
        }
    }
}
