// Tests/HTMLTemplateTests.swift
import XCTest
@testable import Shared

final class HTMLTemplateTests: XCTestCase {

    func testTemplateContainsContent() {
        let html = HTMLTemplate.wrap(body: "<p>Hello</p>", rendererType: "markdown")
        XCTAssertTrue(html.contains("<p>Hello</p>"))
    }

    func testTemplateHasDarkModeCSS() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "plaintext")
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    func testTemplateIncludesRendererTypeClass() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "notebook")
        XCTAssertTrue(html.contains("class=\"notebook\""))
    }

    func testTemplateWithCustomCSS() {
        let css = "--custom-font: Menlo; --custom-size: 16px;"
        let html = HTMLTemplate.wrap(body: "<pre>test</pre>", rendererType: "plaintext", customCSS: css)
        XCTAssertTrue(html.contains(css))
    }

    func testTemplateIncludesJSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        XCTAssertTrue(html.contains("marked.min.js"))
        XCTAssertTrue(html.contains("highlight.min.js"))
        XCTAssertTrue(html.contains("katex.min.js"))
    }

    func testTemplateCSPAllowsOnlyBundledAndNoncedScripts() {
        let html = HTMLTemplate.wrap(
            body: "<script nonce=\"\(HTMLTemplate.scriptNoncePlaceholder)\">trusted()</script>",
            rendererType: "markdown"
        )
        let nonce = cspNonce(in: html)

        XCTAssertTrue(html.contains("http-equiv=\"Content-Security-Policy\""))
        XCTAssertNotNil(nonce)
        XCTAssertTrue(html.contains("script-src 'self' 'nonce-\(nonce ?? "")'"))
        XCTAssertTrue(html.contains("<script nonce=\"\(nonce ?? "")\">trusted()</script>"))
        XCTAssertFalse(html.contains(HTMLTemplate.scriptNoncePlaceholder))
        XCTAssertFalse(html.contains("script-src 'unsafe-inline'"))
        XCTAssertTrue(html.contains("object-src 'none'"))
        XCTAssertTrue(html.contains("frame-src 'none'"))
    }

    func testTemplateUsesUniqueNoncePerDocument() {
        let first = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        let second = HTMLTemplate.wrap(body: "", rendererType: "markdown")

        XCTAssertNotEqual(cspNonce(in: first), cspNonce(in: second))
    }

    private func cspNonce(in html: String) -> String? {
        let prefix = "script-src 'self' 'nonce-"
        guard let suffix = html.range(of: prefix)?.upperBound else { return nil }
        return html[suffix...].split(separator: "'", maxSplits: 1).first.map(String.init)
    }
}
