// Tests/SyntaxLanguageMapTests.swift
import XCTest
@testable import Shared

/// The map exists to answer one question Swift cannot ask the web view:
/// "does the bundled highlight.js know a language for this extension?"
/// Every id it returns must be registered in the bundled `common` build,
/// or the preview silently falls back to no-highlight.
final class SyntaxLanguageMapTests: XCTestCase {

    func testMapsTheReportedDataFormats() {
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "json"), "json")
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "yaml"), "yaml")
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "yml"), "yaml")
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "toml"), "ini")
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "JSON"), "json")
        XCTAssertEqual(SyntaxLanguageMap.language(forExtension: "YML"), "yaml")
    }

    func testMapsCommonSourceExtensions() {
        let expected: [String: String] = [
            "swift": "swift", "py": "python", "rb": "ruby", "go": "go", "rs": "rust",
            "js": "javascript", "mjs": "javascript", "ts": "typescript", "tsx": "typescript",
            "java": "java", "kt": "kotlin", "c": "c", "h": "c", "cpp": "cpp", "hpp": "cpp",
            "cs": "csharp", "m": "objectivec", "sh": "bash", "zsh": "bash", "sql": "sql",
            "css": "css", "scss": "scss", "less": "less", "xml": "xml", "html": "xml",
            "lua": "lua", "pl": "perl", "r": "r", "php": "php", "diff": "diff",
            "graphql": "graphql", "ini": "ini", "makefile": "makefile",
        ]
        for (ext, language) in expected {
            XCTAssertEqual(SyntaxLanguageMap.language(forExtension: ext), language, "\(ext) mapped wrong")
        }
    }

    /// `log` drives the bounded log-level pattern path, not hljs. Handing it a
    /// language would divert `PlainTextRenderer` into the syntax branch and
    /// drop every configured level pattern.
    func testDoesNotMapLogOrPlainText() {
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: "log"))
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: "txt"))
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: ""))
    }

    func testReturnsNilForUnknownExtension() {
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: "dockerfile"))
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: "tf"))
        XCTAssertNil(SyntaxLanguageMap.language(forExtension: "zzz"))
    }

    /// Guards the map against drift from the bundled build: every value it can
    /// return must be a language id the shipped highlight.js registers.
    func testEveryMappedLanguageIsInTheBundledBuild() throws {
        let url = try XCTUnwrap(
            Bundle(for: ConfigLoader.self).url(forResource: "highlight.min", withExtension: "js"),
            "bundled highlight.min.js missing"
        )
        let source = try String(contentsOf: url, encoding: .utf8)
        for language in Set(SyntaxLanguageMap.allLanguages) {
            XCTAssertTrue(
                source.contains("grmr_\(language.replacingOccurrences(of: "-", with: "_")):"),
                "highlight.js does not register '\(language)'"
            )
        }
    }

    func testAllLanguagesHasNoDuplicates() {
        XCTAssertEqual(
            SyntaxLanguageMap.allLanguages.count,
            Set(SyntaxLanguageMap.allLanguages).count
        )
    }
}
