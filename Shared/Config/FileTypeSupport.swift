import Foundation
import UniformTypeIdentifiers

/// Eligibility follows the installed extension's declarations, not config.json.
/// macOS still chooses the actual provider when several extensions qualify.
public struct FileTypeSupport {
    public enum Status: Equatable { case eligible, unsupported, unknown }
    public enum InputError: LocalizedError {
        case invalidExtension
        public var errorDescription: String? { "Enter one extension, such as yaml, without a path or spaces." }
    }
    private let supportedTypeIdentifiers: [String]

    public init(supportedTypeIdentifiers: [String]) {
        self.supportedTypeIdentifiers = supportedTypeIdentifiers
    }

    public static func bundled(in app: Bundle = .main) -> FileTypeSupport {
        let plugins = app.builtInPlugInsURL
        let urls = plugins.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        let types = urls.filter { $0.pathExtension == "appex" }.compactMap(Bundle.init(url:)).flatMap { bundle -> [String] in
            let ext = bundle.infoDictionary?["NSExtension"] as? [String: Any]
            let attrs = ext?["NSExtensionAttributes"] as? [String: Any]
            return attrs?["QLSupportedContentTypes"] as? [String] ?? []
        }
        return FileTypeSupport(supportedTypeIdentifiers: types)
    }

    public static func normalizedExtension(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix(".") { value.removeFirst() }
        guard !value.isEmpty, value.count <= 64,
              value.range(of: "^[a-z0-9][a-z0-9_+-]*$", options: .regularExpression) != nil else { return nil }
        return value
    }

    public func status(for fileExtension: String) -> Status {
        guard let ext = Self.normalizedExtension(fileExtension),
              let type = UTType(filenameExtension: ext), !type.isDynamic else { return .unknown }
        if supportedTypeIdentifiers.contains(type.identifier) { return .eligible }
        return supportedTypeIdentifiers.compactMap(UTType.init).contains { type.conforms(to: $0) } ? .eligible : .unsupported
    }

    public func adding(_ input: String, to original: AppConfig) throws -> AppConfig {
        guard let ext = Self.normalizedExtension(input) else { throw InputError.invalidExtension }
        var config = original
        if config.fileTypes?[ext] != nil { return config }
        if config.fileTypes == nil { config.fileTypes = [:] }
        config.fileTypes?[ext] = FileTypeConfig()
        return config
    }
}
