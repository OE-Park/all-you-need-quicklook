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

    /// The bundled libraries must be inlined, not linked: a document loaded
    /// with `loadHTMLString(_:baseURL:)` cannot fetch subresources from the
    /// file:// baseURL, so a `<script src>` or `<link href>` never runs.
    func testTemplateInlinesJSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        XCTAssertTrue(html.contains("marked v15"), "marked.js source not inlined")
        XCTAssertTrue(html.contains("var hljs="), "highlight.js source not inlined")
        XCTAssertTrue(html.contains("e.katex=t()"), "KaTeX source not inlined")
    }

    func testTemplateInlinesCSSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
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
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        let headEnd = try XCTUnwrap(html.range(of: "</head>")).lowerBound
        let head = String(html[..<headEnd])
        XCTAssertEqual(head.components(separatedBy: "</script>").count - 1, 3)
        XCTAssertEqual(head.components(separatedBy: "</style>").count - 1, 4)
    }

    /// The template must reference no external subresource, because the CSP
    /// names no script or style source beyond `'unsafe-inline'`.
    func testTemplateReferencesNoExternalSubresources() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        XCTAssertFalse(html.contains("<script src="), "template still links external JS")
        XCTAssertFalse(html.contains("<link rel=\"stylesheet\""), "template still links external CSS")
    }
}
