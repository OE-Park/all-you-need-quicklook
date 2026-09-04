// Shared/Config/ConfigLoader.swift
import Foundation

public final class ConfigLoader: Sendable {
    private let containerURL: URL
    private let configFileName = "config.json"

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public convenience init() {
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yohanpark.AllYouNeedQuickLook"
        ) ?? FileManager.default.temporaryDirectory
        self.init(containerURL: groupURL)
    }

    private var configFileURL: URL {
        containerURL.appendingPathComponent(configFileName)
    }

    public func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return Self.bundledDefault()
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return Self.bundledDefault()
        }
    }

    public func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
    }

    /// The shipped default configuration — `Shared/Resources/default-config.json`.
    ///
    /// Public because it is the *only* way back: `load()` falls back to it only
    /// while no `config.json` exists, and the first `save()` ends that forever.
    /// A "Reset to Default" that assigned `AppConfig()` instead would write a
    /// config with no `fileTypes` at all — silently dropping the `log` level
    /// patterns for every preview, in the QuickLook extension too, with nothing
    /// in the app able to bring them back.
    ///
    /// Falls back to `AppConfig()` only when the bundled resource is missing,
    /// which would mean a broken build.
    public static func bundledDefault() -> AppConfig {
        guard let url = Bundle(for: ConfigLoader.self).url(forResource: "default-config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return config
    }
}
