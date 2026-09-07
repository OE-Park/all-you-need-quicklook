// Tests/HTMLTemplateTests.swift
import XCTest
@testable import Shared

final class HTMLTemplateTests: XCTestCase {

    private let nonce = "TESTNONCE"

    func testTemplateContainsContent() {
        let html = HTMLTemplate.wrap(body: "<p>Hello</p>", rendererType: "markdown", nonce: nonce)
        XCTAssertTrue(html.contains("<p>Hello</p>"))
    }

    func testTemplateHasDarkModeCSS() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "plaintext", nonce: nonce)
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    func testTemplateIncludesRendererTypeClass() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "notebook", nonce: nonce)
        XCTAssertTrue(html.contains("class=\"notebook\""))
    }

    func testTemplateWithCustomCSS() {
        let css = "--custom-font: Menlo; --custom-size: 16px;"
        let html = HTMLTemplate.wrap(body: "<pre>test</pre>", rendererType: "plaintext", nonce: nonce, customCSS: css)
        XCTAssertTrue(html.contains(css))
    }

    /// The bundled libraries must be inlined, not linked: a document loaded
    /// with `loadHTMLString(_:baseURL:)` cannot fetch subresources from the
    /// file:// baseURL, so a `<script src>` or `<link href>` never runs.
    func testTemplateInlinesJSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        XCTAssertTrue(html.contains("marked v15"), "marked.js source not inlined")
        XCTAssertTrue(html.contains("var hljs="), "highlight.js source not inlined")
        XCTAssertTrue(html.contains("e.katex=t()"), "KaTeX source not inlined")
    }

    func testTemplateInlinesCSSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        XCTAssertTrue(html.contains("font-family:KaTeX_AMS"), "KaTeX CSS not inlined")
        XCTAssertTrue(html.contains("<style media=\"(prefers-color-scheme: light)\">"))
        XCTAssertTrue(html.contains("<style media=\"(prefers-color-scheme: dark)\">"))
        XCTAssertTrue(html.contains("pre code.hljs"), "highlight.js themes not inlined")
    }

    func testBundledLibrariesResolveFromFramework() {
        for (label, source) in [
            ("katex.min.css", HTMLTemplate.katexCSS),
            ("highlight-light.min.css", HTMLTemplate.highlightLightCSS),
            ("highlight-dark.min.css", HTMLTemplate.highlightDarkCSS),
            ("marked.min.js", HTMLTemplate.markedJS),
            ("highlight.min.js", HTMLTemplate.highlightJS),
            ("katex.min.js", HTMLTemplate.katexJS)
        ] {
            XCTAssertFalse(source.isEmpty, "\(label) missing from the Shared framework bundle")
        }
    }

    /// Nothing inlined may close its own container element early.
    func testInlinedLibrariesCannotEscapeTheirElement() throws {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        let headEnd = try XCTUnwrap(html.range(of: "</head>")).lowerBound
        let head = String(html[..<headEnd])
        XCTAssertEqual(head.components(separatedBy: "</script>").count - 1, 3)
        XCTAssertEqual(head.components(separatedBy: "</style>").count - 1, 4)
    }

    /// Every `<script>` the template emits must carry the load's nonce, or
    /// `script-src 'nonce-…'` refuses it and the preview renders as raw text.
    func testTemplateStampsTheNonceOnEveryScriptItEmits() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        // Counted by the stamped opening tag rather than by `<script`, which
        // also occurs inside the minified library sources themselves. Three
        // openings to match the three `</script>` closings
        // `testInlinedLibrariesCannotEscapeTheirElement` pins.
        XCTAssertEqual(html.components(separatedBy: "<script nonce=\"\(nonce)\">").count - 1, 4,
                       "a bundled library <script> is missing this document's nonce")
    }

    /// The template must reference no external subresource, because the CSP
    /// names no script or style source beyond the nonce and `'unsafe-inline'`
    /// style.
    func testTemplateReferencesNoExternalSubresources() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        XCTAssertFalse(html.contains("<script src="), "template still links external JS")
        XCTAssertFalse(html.contains("<link rel=\"stylesheet\""), "template still links external CSS")
    }

    func testTemplateCSPAllowsOnlyBundledAndNoncedScripts() {
        let html = HTMLTemplate.wrap(
            body: "<script nonce=\"\(nonce)\">trusted()</script>",
            rendererType: "markdown", nonce: nonce
        )
        let nonce = cspNonce(in: html)

        XCTAssertTrue(html.contains("http-equiv=\"Content-Security-Policy\""))
        XCTAssertNotNil(nonce)
        XCTAssertTrue(html.contains("script-src 'nonce-\(nonce ?? "")'"))
        XCTAssertTrue(html.contains("<script nonce=\"\(nonce ?? "")\">trusted()</script>"))
        XCTAssertFalse(html.contains("script-src 'unsafe-inline'"))
        XCTAssertTrue(html.contains("default-src 'none'"))

    }

    func testTemplateUsesUniqueNoncePerDocument() {
        let first = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: PreviewWebView.makeNonce())
        let second = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: PreviewWebView.makeNonce())

        XCTAssertNotEqual(cspNonce(in: first), cspNonce(in: second))
    }

    private func cspNonce(in html: String) -> String? {
        let prefix = "script-src 'nonce-"
        guard let suffix = html.range(of: prefix)?.upperBound else { return nil }
        return html[suffix...].split(separator: "'", maxSplits: 1).first.map(String.init)
    }
}
