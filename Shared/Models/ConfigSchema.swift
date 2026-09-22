// Shared/Models/ConfigSchema.swift
import Foundation

public struct GlobalConfig: Codable, Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Int
    public var lineHeight: Double
    public var showLineNumbers: Bool
    public var imageTimeoutSeconds: Int
    public var allowExternalImages: Bool

    public init(
        fontFamily: String = "SF Mono",
        fontSize: Int = 13,
        lineHeight: Double = 1.5,
        showLineNumbers: Bool = true,
        imageTimeoutSeconds: Int = 3,
        allowExternalImages: Bool = false
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.showLineNumbers = showLineNumbers
        self.imageTimeoutSeconds = imageTimeoutSeconds
        self.allowExternalImages = allowExternalImages
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, lineHeight, showLineNumbers, imageTimeoutSeconds, allowExternalImages
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try values.decode(String.self, forKey: .fontFamily)
        fontSize = try values.decode(Int.self, forKey: .fontSize)
        lineHeight = try values.decode(Double.self, forKey: .lineHeight)
        showLineNumbers = try values.decode(Bool.self, forKey: .showLineNumbers)
        imageTimeoutSeconds = try values.decode(Int.self, forKey: .imageTimeoutSeconds)
        allowExternalImages = try values.decodeIfPresent(Bool.self, forKey: .allowExternalImages) ?? false
    }
}

public struct FileTypeConfig: Codable, Equatable, Sendable {
    public var fontFamily: String?
    public var fontSize: Int?
    public var lineHeight: Double?
    public var showLineNumbers: Bool?
    public var syntaxHighlight: Bool?
    public var syntaxLanguage: String?
    public var logLevelPatterns: [String: String]?

    public init(
        fontFamily: String? = nil,
        fontSize: Int? = nil,
        lineHeight: Double? = nil,
        showLineNumbers: Bool? = nil,
        syntaxHighlight: Bool? = nil,
        syntaxLanguage: String? = nil,
        logLevelPatterns: [String: String]? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.showLineNumbers = showLineNumbers
        self.syntaxHighlight = syntaxHighlight
        self.syntaxLanguage = syntaxLanguage
        self.logLevelPatterns = logLevelPatterns
    }
}

public struct ResolvedFileTypeConfig: Sendable {
    public let fontFamily: String
    public let fontSize: Int
    public let lineHeight: Double
    public let showLineNumbers: Bool
    public let syntaxHighlight: Bool
    public let syntaxLanguage: String?
    public let logLevelPatterns: [String: String]?
}

extension FileTypeConfig {
    /// Resolves this entry against the global defaults for a concrete file.
    ///
    /// `fileExtension` is what lets an unconfigured — or bare, Settings-added —
    /// entry still highlight: with no explicit `syntaxLanguage`, the extension
    /// is looked up in `SyntaxLanguageMap`, and highlighting defaults on only
    /// when that lookup found a grammar the bundled highlight.js actually has.
    /// Explicit values always win, in both directions.
    ///
    /// Log level patterns suppress the lookup. `PlainTextRenderer` takes the
    /// hljs branch whenever a language is present, so inferring one for a file
    /// configured with patterns would silently discard them.
    public func resolved(with global: GlobalConfig, fileExtension: String) -> ResolvedFileTypeConfig {
        let hasLogPatterns = !(logLevelPatterns?.isEmpty ?? true)
        let language = syntaxLanguage
            ?? (hasLogPatterns ? nil : SyntaxLanguageMap.language(forExtension: fileExtension))
        return ResolvedFileTypeConfig(
            fontFamily: fontFamily ?? global.fontFamily,
            fontSize: fontSize ?? global.fontSize,
            lineHeight: lineHeight ?? global.lineHeight,
            showLineNumbers: showLineNumbers ?? global.showLineNumbers,
            syntaxHighlight: syntaxHighlight ?? (language != nil),
            syntaxLanguage: language,
            logLevelPatterns: logLevelPatterns
        )
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var global: GlobalConfig
    public var fileTypes: [String: FileTypeConfig]?

    public init(
        version: Int = 1,
        global: GlobalConfig = GlobalConfig(),
        fileTypes: [String: FileTypeConfig]? = nil
    ) {
        self.version = version
        self.global = global
        self.fileTypes = fileTypes
    }

    public func resolvedConfig(for fileExtension: String) -> ResolvedFileTypeConfig {
        let fileType = fileTypes?[fileExtension] ?? FileTypeConfig()
        return fileType.resolved(with: global, fileExtension: fileExtension)
    }
}
