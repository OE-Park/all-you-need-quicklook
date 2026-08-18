// Tests/MarkdownRendererTests.swift
import XCTest
@testable import Shared

final class MarkdownRendererTests: XCTestCase {

    let renderer = MarkdownRenderer()
    let config = AppConfig()

    func testRendersMarkdownInTemplate() {
        let md = "# Hello World\n\nSome **bold** text."
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("class=\"markdown\""))
        XCTAssertTrue(html.contains("# Hello World"))
        XCTAssertTrue(html.contains("marked.min.js"))
    }

    func testContainsMarkedParseScript() {
        let md = "test"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("marked.parse"))
    }

    func testContainsKaTeXRenderScript() {
        let md = "Inline $E=mc^2$ math"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("renderMathInElement") || html.contains("katex"))
    }

    func testEscapesContentForJavaScript() {
        let md = "line with `backtick` and \\ backslash and 'quote'"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("\\\\"))
    }

    func testDoesNotCloseScriptElement() {
        let md = "</script><img src=x>"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertFalse(html.contains("</script><img"))
        XCTAssertFalse(html.contains("</SCRIPT><img"))
    }
}
