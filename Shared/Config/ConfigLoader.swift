// Shared/Config/ConfigLoader.swift
import Foundation
import os

/// What a read of `config.json` produced, and whether the file was there but
/// could not be used (so the caller can say so instead of silently showing defaults).
public struct ConfigLoadResult: Sendable {
    public let config: AppConfig
    public let isUnreadable: Bool
}

public final class ConfigLoader: Sendable {
    public static let didSave = Notification.Name("QuickLookConfigurationDidSave")
    private let containerURL: URL
    private let configFileName = "config.json"

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    /// `~/Library/Application Support/AllYouNeedQuickLook` under the *real* home.
    ///
    /// `NSHomeDirectory()` inside a sandbox is the container, so the real home
    /// comes from the password database. The host may write here through a
    /// home-relative entitlement and the extension reads it through a read-only
    /// absolute-path entitlement; no App Group is involved.
    public static var defaultDirectory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/AllYouNeedQuickLook", isDirectory: true)
    }

    public convenience init() {
        self.init(containerURL: Self.defaultDirectory)
    }

    private static let logger = Logger(subsystem: "com.yohanpark.AllYouNeedQuickLook", category: "config")

    private var configFileURL: URL {
        containerURL.appendingPathComponent(configFileName)
    }

    public func load() -> AppConfig {
        loadResult().config
    }

    /// A missing file is the normal first-run state and yields the bundled
    /// default with `isUnreadable == false`. A file that exists but cannot be
    /// read or decoded yields the same default with `isUnreadable == true`.
    public func loadResult() -> ConfigLoadResult {
        do {
            let data = try Data(contentsOf: configFileURL)
            return ConfigLoadResult(config: try JSONDecoder().decode(AppConfig.self, from: data), isUnreadable: false)
        } catch {
            let errorCode = (error as NSError)
            if errorCode.domain == NSCocoaErrorDomain &&
                (errorCode.code == NSFileReadNoSuchFileError || errorCode.code == NSFileNoSuchFileError) {
                return ConfigLoadResult(config: Self.bundledDefault(), isUnreadable: false)
            }
            Self.logger.error("Could not read \(self.configFileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return ConfigLoadResult(config: Self.bundledDefault(), isUnreadable: true)
        }
    }

    public func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try data.write(to: configFileURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didSave, object: nil)
    }

    /// Persist only the new extension against disk state; keep unrelated draft edits in memory.
    public func saveAddedFileType(_ input: String, draft: AppConfig) throws -> AppConfig {
        let support = FileTypeSupport(supportedTypeIdentifiers: [])
        let current = loadResult()
        guard !current.isUnreadable else { throw CocoaError(.fileReadNoPermission) }
        let saved = try support.adding(input, to: current.config)
        if saved != current.config { try save(saved) }
        return try support.adding(input, to: draft)
    }

    /// Explicit user-selected import, including readable legacy App Group JSON.
    /// Decode before writing, so a malformed import never replaces saved settings.
    public func importConfiguration(from url: URL) throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        try save(config)
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
