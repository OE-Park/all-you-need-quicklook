import WebKit
import XCTest
@testable import Shared

@MainActor
final class RendererRegressionTests: XCTestCase {
    func testMathPreservesEscapedDollarInsideExpression() async throws {
        let source = #"Price $\text{price: \$5}$ and $$\text{cost: \$10}$$. Literal \$HOME\$. <code id="raw-code">$RAW$</code>"#
        for ext in ["md", "ipynb"] {
            let renderer: any Renderer = ext == "md" ? MarkdownRenderer() : NotebookRenderer()
            let web = try await load(renderer, ext == "md" ? source : notebook(source), ext: ext)
            let math = try await string("Array.from(document.querySelectorAll('.katex annotation')).map(e => e.textContent).join('|')", in: web)
            XCTAssertEqual(math, #"\text{price: \$5}|\text{cost: \$10}"#, ext)
            let text = try await string("document.querySelector('p').textContent", in: web)
            XCTAssertTrue(text.contains("Literal $HOME$."), text)
            let code = try await string("document.getElementById('raw-code').textContent", in: web)
            XCTAssertEqual(code, "$RAW$", ext)
        }
    }

    func testEscapedDollarRemainsLiteralInMarkdownAndNotebook() async throws {
        let source = "Literal \\$HOME\\$ and $E=mc^2$. Code: `\\$CODE\\$`"
        for ext in ["md", "ipynb"] {
            let renderer: any Renderer = ext == "md" ? MarkdownRenderer() : NotebookRenderer()
            let web = try await load(renderer, ext == "md" ? source : notebook(source), ext: ext)
            let math = try await string("Array.from(document.querySelectorAll('.katex annotation')).map(e => e.textContent).join('|')", in: web)
            XCTAssertEqual(math, "E=mc^2", ext)
            let text = try await string("document.querySelector('p').textContent", in: web)
            XCTAssertTrue(text.contains("Literal $HOME$"), text)
            let code = try await string("document.querySelector('code').textContent", in: web)
            XCTAssertEqual(code, "\\$CODE\\$", ext)
        }
    }

    func testBlockingExternalImagesStillDisplaysEmbeddedDataImage() async throws {
        let source = "![pixel](data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==)"
        let web = try await load(MarkdownRenderer(), source, ext: "md")
        let width = try await string("document.querySelector('img')?.naturalWidth", in: web)
        XCTAssertEqual(width, "1")
        let notices = try await string("document.querySelectorAll('.external-image-blocked').length", in: web)
        XCTAssertEqual(notices, "0")
    }

    func testDefaultImagePolicyShowsNoticeForRemoteAndDirectProxyImages() async throws {
        let source = "<img src='https://example.test/x.png'><img src='quicklook-image://fetch/?url=http%3A%2F%2F127.0.0.1%2Fx'>"
        let web = try await load(MarkdownRenderer(), source, ext: "md")
        let count = try await string("document.querySelectorAll('.external-image-blocked').length", in: web)
        XCTAssertEqual(count, "2")
        let requests = try await string("document.querySelectorAll('img').length", in: web)
        XCTAssertEqual(requests, "0")
    }

    func testLegacyConfigDefaultsToBlockingExternalImages() throws {
        let data = Data(#"{"version":1,"global":{"fontFamily":"SF Mono","fontSize":13,"lineHeight":1.5,"showLineNumbers":true,"imageTimeoutSeconds":3}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        let global = encoded["global"] as! [String: Any]
        XCTAssertEqual(global["allowExternalImages"] as? Bool, false)
    }

    func testHighlightedTextUsesConfiguredFontAndOptionalLineNumbers() async throws {
        for numbers in [true, false] {
            var config = AppConfig()
            config.fileTypes = ["txt": FileTypeConfig(fontFamily: "Courier", fontSize: 17, lineHeight: 2, showLineNumbers: numbers, syntaxHighlight: true, syntaxLanguage: "plaintext")]
            let web = try await load(PlainTextRenderer(), "first\nsecond\n", ext: "txt", config: config)
            let text = try await string("document.getElementById('code-content').textContent", in: web)
            XCTAssertEqual(text, "first\nsecond\n")
            let count = try await string("document.querySelectorAll('.line-number').length", in: web)
            XCTAssertEqual(count, numbers ? "3" : "0")
            let fonts = try await string("getComputedStyle(document.getElementById('code-content')).fontFamily", in: web)
            XCTAssertTrue(fonts.contains("Courier"), fonts)
        }
    }

    func testLogMatchingPreservesEntitiesUnicodeAndLevelPrecedence() async throws {
        var config = AppConfig()
        config.fileTypes = ["log": FileTypeConfig(showLineNumbers: false, logLevelPatterns: ["error": "&|ERROR|😀", "warn": "ERROR"])]
        let web = try await load(PlainTextRenderer(), "a < b & c 😀 ERROR", ext: "log", config: config)
        let text = try await string("document.querySelector('.plaintext-content').textContent", in: web)
        XCTAssertEqual(text, "a < b & c 😀 ERROR")
        let errors = try await string("Array.from(document.querySelectorAll('.log-error')).map(e => e.textContent).join('|')", in: web)
        XCTAssertEqual(errors, "&|😀|ERROR")
        let warnings = try await string("document.querySelectorAll('.log-warn').length", in: web)
        XCTAssertEqual(warnings, "0")
    }

    func testUnsupportedAndExhaustedLogPatternsLeaveReadableTextAndNotice() async throws {
        for (pattern, text) in [("(?=ERROR)ERROR", "ERROR"), ("a[a]*b|a", String(repeating: "a", count: 16000))] {
            var config = AppConfig()
            config.fileTypes = ["log": FileTypeConfig(showLineNumbers: false, logLevelPatterns: ["error": pattern])]
            let web = try await load(PlainTextRenderer(), text, ext: "log", config: config)
            let visible = try await string("document.querySelector('.plaintext-content').textContent", in: web)
            XCTAssertEqual(visible, text)
            let notice = try await string("document.querySelectorAll('.highlight-skipped').length", in: web)
            XCTAssertEqual(notice, "1")
        }
    }

    func testOversizedPlainTextHasBoundedOutputAndTruncationNotice() async throws {
        var config = AppConfig()
        config.global.showLineNumbers = false
        let web = try await load(PlainTextRenderer(), String(repeating: "😀\n", count: 150000), ext: "txt", config: config)
        let count = try await string("document.querySelector('.plaintext-content').textContent.length", in: web)
        XCTAssertLessThanOrEqual(Int(count) ?? Int.max, 262144)
        let notice = try await string("document.querySelectorAll('.preview-truncated').length", in: web)
        XCTAssertEqual(notice, "1")
        let replacement = try await string("document.querySelector('.plaintext-content').textContent.includes('�')", in: web)
        XCTAssertEqual(replacement, "false")
    }

    func testMathLeavesCodeAndAttributesIntactInMarkdownAndNotebook() async throws {
        let source = "```sh\necho '$HOME$'\n```\n\n`$CODE$`\n\n<span id=\"attr\" title=\"$TITLE$\">literal</span>\n\nInline $a < b$ and $$c+d$$"
        for ext in ["md", "ipynb"] {
            let renderer: any Renderer = ext == "md" ? MarkdownRenderer() : NotebookRenderer()
            let web = try await load(renderer, ext == "md" ? source : notebook(source), ext: ext)
            let code = try await string("document.querySelector('pre code').textContent", in: web)
            XCTAssertEqual(code, "echo '$HOME$'\n", ext)
            let inline = try await string("document.querySelector('p code').textContent", in: web)
            XCTAssertEqual(inline, "$CODE$", ext)
            let title = try await string("document.getElementById('attr')?.getAttribute('title')", in: web)
            XCTAssertEqual(title, "$TITLE$", ext)
            let annotations = try await string("Array.from(document.querySelectorAll('.katex annotation')).map(e => e.textContent).join('|')", in: web)
            XCTAssertEqual(annotations, "a < b|c+d", ext)
        }
    }

    func testNotebookMarkdownRecoversSourceBeforeParsing() async throws {
        let web = try await load(NotebookRenderer(), notebook("`a < b & c`\n\n<b>bold</b>"), ext: "ipynb")
        let code = try await string("document.querySelector('.markdown-cell code').textContent", in: web)
        XCTAssertEqual(code, "a < b & c")
        let bold = try await string("document.querySelector('.markdown-cell b')?.textContent", in: web)
        XCTAssertEqual(bold, "bold")
    }

    private func notebook(_ source: String) throws -> String {
        let value: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "cells": [["cell_type": "markdown", "source": source]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    func testMarkdownCommentAndScriptOpeningCannotSwallowDocument() async throws {
        let web = try await load(MarkdownRenderer(), "# Visible\n\n<!--<script>", ext: "md")
        let heading = try await string("document.querySelector('h1')?.textContent", in: web)
        XCTAssertEqual(heading, "Visible")
        let ready = try await string("document.documentElement.dataset.quicklookReady", in: web)
        XCTAssertEqual(ready, "true")
    }

    func testHighlightedScriptBoundariesPreserveLiteralContent() async throws {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(showLineNumbers: false, syntaxHighlight: true, syntaxLanguage: "plaintext")]
        let source = "before <!--<script> after </script><script>globalThis.pwned=1</script>"
        let web = try await load(PlainTextRenderer(), source, ext: "txt", config: config)
        let text = try await string("document.getElementById('code-content')?.textContent", in: web)
        XCTAssertEqual(text, source)
        let pwned = try await string("typeof globalThis.pwned", in: web)
        XCTAssertEqual(pwned, "undefined")
    }

    private func load(_ renderer: any Renderer, _ content: String, ext: String, config: AppConfig = AppConfig()) async throws -> PreviewWebView {
        let nonce = PreviewWebView.makeNonce()
        let web = PreviewWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        web.loadHTML(renderer.render(content: content, config: config, fileExtension: ext, nonce: nonce),
                     resourcesURL: Bundle(for: ConfigLoader.self).resourceURL, nonce: nonce)
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("document.documentElement.dataset.quicklookReady === 'true'")) as? Bool == true {
                return web
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Document renderer did not become ready")
        return web
    }

    private func string(_ expression: String, in web: WKWebView) async throws -> String {
        let value = try await web.evaluateJavaScript("String(\(expression))")
        return try XCTUnwrap(value as? String)
    }
}
