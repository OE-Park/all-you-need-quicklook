// Tests/PlainTextRendererTests.swift
import XCTest
@testable import Shared

final class PlainTextRendererTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

    let renderer = PlainTextRenderer()

    func testBasicTextRendering() {
        let config = AppConfig()
        let html = renderer.render(content: "Hello world", config: config, fileExtension: "txt", nonce: nonce)
        XCTAssertTrue(html.contains("class=\"plaintext\""))
        XCTAssertTrue(html.contains("Hello world"))
        XCTAssertTrue(html.contains("<pre"))
    }

    func testAppliesCustomFont() {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(fontFamily: "Menlo", fontSize: 16)]
        let html = renderer.render(content: "test", config: config, fileExtension: "txt", nonce: nonce)
        XCTAssertTrue(html.contains("Menlo"))
        XCTAssertTrue(html.contains("16px"))
    }

    func testLogLevelHighlighting() {
        var config = AppConfig()
        config.fileTypes = [
            "log": FileTypeConfig(
                syntaxHighlight: true,
                logLevelPatterns: [
                    "error": "\\b(ERROR)\\b",
                    "warn": "\\b(WARN)\\b",
                    "info": "\\b(INFO)\\b"
                ]
            )
        ]
        let logContent = "[2024-01-01] ERROR Something failed\n[2024-01-01] INFO All good\n[2024-01-01] WARN Be careful"
        let html = renderer.render(content: logContent, config: config, fileExtension: "log", nonce: nonce)
        XCTAssertTrue(html.contains("log-error"))
        XCTAssertTrue(html.contains("log-info"))
        XCTAssertTrue(html.contains("log-warn"))
    }

    func testLineNumbers() {
        var config = AppConfig()
        config.global.showLineNumbers = true
        let html = renderer.render(content: "line1\nline2\nline3", config: config, fileExtension: "txt", nonce: nonce)
        XCTAssertTrue(html.contains("<span class=\"line-number\">"))
    }

    func testNoLineNumbersWhenDisabled() {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(showLineNumbers: false)]
        let html = renderer.render(content: "line1\nline2", config: config, fileExtension: "txt", nonce: nonce)
        XCTAssertFalse(html.contains("<span class=\"line-number\">"))
    }

    func testSyntaxHighlightWithLanguage() {
        var config = AppConfig()
        config.fileTypes = ["plist": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "xml")]
        let html = renderer.render(content: "<plist></plist>", config: config, fileExtension: "plist", nonce: nonce)
        XCTAssertTrue(html.contains("hljs.highlight"))
        XCTAssertTrue(html.contains("xml"))
    }

    func testHTMLEscaping() {
        let config = AppConfig()
        let html = renderer.render(content: "<script>alert('xss')</script>", config: config, fileExtension: "txt", nonce: nonce)
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testApostropheEscaped() {
        let html = renderer.render(content: "it's unsafe", config: AppConfig(), fileExtension: "txt", nonce: nonce)

        XCTAssertTrue(html.contains("it&#39;s unsafe"))
    }

    func testSyntaxLanguageCannotBreakOutOfJavaScriptString() {
        var config = AppConfig()
        config.fileTypes = [
            "txt": FileTypeConfig(
                syntaxHighlight: true,
                syntaxLanguage: "swift');globalThis.pwned=true;//"
            )
        ]

        let html = renderer.render(content: "let x = 1", config: config, fileExtension: "txt", nonce: nonce)

        XCTAssertFalse(html.contains("language: 'swift');globalThis.pwned=true;//'"))
    }

    func testHighlightedContentCannotCloseScriptElement() {
        var config = AppConfig()
        config.fileTypes = [
            "txt": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "plaintext")
        ]

        let html = renderer.render(
            content: "</script><script nonce=\"known-nonce\">globalThis.pwned=true</script>",
            config: config,
            fileExtension: "txt", nonce: nonce
        )

        XCTAssertFalse(html.contains("</script><script nonce="))
        XCTAssertTrue(html.contains("<\\/script>"))
    }

    // MARK: - Data formats added via Settings

    /// The reported defect: a .json file added in Settings stored a bare
    /// `FileTypeConfig()` and rendered as uncoloured plain text.
    func testJSONHighlightsWithNoExplicitConfiguration() {
        var config = AppConfig()
        config.fileTypes = ["json": FileTypeConfig()]
        let html = renderer.render(content: "{\"a\": 1}", config: config, fileExtension: "json", nonce: nonce)
        XCTAssertTrue(html.contains("id=\"code-content\""), "did not take the syntax path")
        XCTAssertTrue(html.contains("language-json"))
        XCTAssertTrue(html.contains("hljs.getLanguage('json')"))
    }

    func testYAMLHighlightsForBothExtensions() {
        for ext in ["yaml", "yml"] {
            let html = renderer.render(content: "a: 1", config: AppConfig(), fileExtension: ext, nonce: nonce)
            XCTAssertTrue(html.contains("language-yaml"), "\(ext) did not resolve to yaml")
        }
    }

    /// highlight.js has no TOML grammar; `toml` is its own alias for `ini`.
    func testTOMLHighlightsAsINI() {
        let html = renderer.render(content: "a = 1", config: AppConfig(), fileExtension: "toml", nonce: nonce)
        XCTAssertTrue(html.contains("language-ini"))
    }

    /// The syntax branch fires whenever a language resolves, so a log file
    /// picking one up would lose every configured level pattern. It must not.
    func testLogStillTakesThePatternPathUnderTheBundledDefaults() {
        let config = ConfigLoader.bundledDefault()
        let html = renderer.render(
            content: "[2024-01-01] ERROR boom", config: config, fileExtension: "log", nonce: nonce
        )
        XCTAssertTrue(html.contains("log-error"), "log level patterns were dropped")
        XCTAssertFalse(html.contains("id=\"code-content\""), "log was diverted onto the syntax path")
    }

    func testUnmappedExtensionStaysPlain() {
        let html = renderer.render(content: "FROM alpine", config: AppConfig(), fileExtension: "dockerfile", nonce: nonce)
        XCTAssertFalse(html.contains("id=\"code-content\""))
        XCTAssertTrue(html.contains("FROM alpine"))
    }
}
