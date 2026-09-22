// Tests/ConfigSchemaTests.swift
import XCTest
@testable import Shared

final class ConfigSchemaTests: XCTestCase {

    func testDecodeFullConfig() throws {
        let json = """
        {
            "version": 1,
            "global": {
                "fontFamily": "SF Mono",
                "fontSize": 13,
                "lineHeight": 1.5,
                "showLineNumbers": true,
                "imageTimeoutSeconds": 3
            },
            "fileTypes": {
                "log": {
                    "syntaxHighlight": true,
                    "logLevelPatterns": {
                        "error": "\\\\b(ERROR)\\\\b",
                        "warn": "\\\\b(WARN)\\\\b"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.fontFamily, "SF Mono")
        XCTAssertEqual(config.global.fontSize, 13)
        XCTAssertEqual(config.fileTypes?["log"]?.syntaxHighlight, true)
        XCTAssertEqual(config.fileTypes?["log"]?.logLevelPatterns?["error"], "\\b(ERROR)\\b")
    }

    func testNullFieldsInheritFromGlobal() throws {
        let global = GlobalConfig(
            fontFamily: "SF Mono",
            fontSize: 13,
            lineHeight: 1.5,
            showLineNumbers: true,
            imageTimeoutSeconds: 3
        )
        let fileType = FileTypeConfig(
            fontFamily: nil,
            fontSize: 16,
            lineHeight: nil,
            showLineNumbers: nil,
            syntaxHighlight: nil,
            syntaxLanguage: nil,
            logLevelPatterns: nil
        )
        let resolved = fileType.resolved(with: global, fileExtension: "txt")
        XCTAssertEqual(resolved.fontFamily, "SF Mono")
        XCTAssertEqual(resolved.fontSize, 16)
        XCTAssertEqual(resolved.lineHeight, 1.5)
        XCTAssertEqual(resolved.showLineNumbers, true)
    }

    func testEncodeRoundTrip() throws {
        let config = AppConfig(
            version: 1,
            global: GlobalConfig(
                fontFamily: "Menlo",
                fontSize: 14,
                lineHeight: 1.6,
                showLineNumbers: false,
                imageTimeoutSeconds: 5
            ),
            fileTypes: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.global.fontFamily, "Menlo")
        XCTAssertEqual(decoded.global.imageTimeoutSeconds, 5)
    }

    // MARK: - Extension-driven syntax language

    /// Adding a type in Settings stores a bare `FileTypeConfig()`. Before the
    /// extension was consulted that meant `syntaxHighlight: false` and
    /// `syntaxLanguage: nil` — a .json file added by the user rendered as
    /// uncoloured plain text, which is the defect this covers.
    func testBareFileTypeGetsLanguageAndHighlightFromExtension() {
        let config = AppConfig(fileTypes: ["json": FileTypeConfig()])
        let resolved = config.resolvedConfig(for: "json")
        XCTAssertEqual(resolved.syntaxLanguage, "json")
        XCTAssertTrue(resolved.syntaxHighlight)
    }

    /// The same has to hold for a type the user never added at all.
    func testUnconfiguredExtensionStillResolvesALanguage() {
        let resolved = AppConfig().resolvedConfig(for: "yml")
        XCTAssertEqual(resolved.syntaxLanguage, "yaml")
        XCTAssertTrue(resolved.syntaxHighlight)
    }

    func testExplicitLanguageWinsOverTheExtension() {
        let config = AppConfig(fileTypes: ["json": FileTypeConfig(syntaxLanguage: "yaml")])
        XCTAssertEqual(config.resolvedConfig(for: "json").syntaxLanguage, "yaml")
    }

    func testExplicitHighlightOffWinsOverTheExtension() {
        let config = AppConfig(fileTypes: ["json": FileTypeConfig(syntaxHighlight: false)])
        let resolved = config.resolvedConfig(for: "json")
        XCTAssertFalse(resolved.syntaxHighlight)
        XCTAssertEqual(resolved.syntaxLanguage, "json", "language still resolves; only highlighting is off")
    }

    func testUnknownExtensionResolvesNoLanguageAndNoHighlight() {
        let resolved = AppConfig().resolvedConfig(for: "dockerfile")
        XCTAssertNil(resolved.syntaxLanguage)
        XCTAssertFalse(resolved.syntaxHighlight)
    }

    /// A config carrying log level patterns must never acquire a language:
    /// `PlainTextRenderer` takes the hljs branch whenever one is present and
    /// would drop the patterns entirely.
    func testLogPatternsSuppressTheExtensionLanguage() {
        let config = AppConfig(fileTypes: [
            "json": FileTypeConfig(logLevelPatterns: ["error": "ERROR"])
        ])
        let resolved = config.resolvedConfig(for: "json")
        XCTAssertNil(resolved.syntaxLanguage)
        XCTAssertFalse(resolved.syntaxHighlight)
    }

    /// The shipped default keeps .log on the pattern path and .txt plain.
    func testBundledDefaultsKeepLogAndTextOffTheSyntaxPath() {
        let config = ConfigLoader.bundledDefault()
        let log = config.resolvedConfig(for: "log")
        XCTAssertNil(log.syntaxLanguage)
        XCTAssertNotNil(log.logLevelPatterns)

        let text = config.resolvedConfig(for: "txt")
        XCTAssertNil(text.syntaxLanguage)
        XCTAssertFalse(text.syntaxHighlight)
    }
}
