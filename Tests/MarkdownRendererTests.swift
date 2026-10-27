// Tests/MarkdownRendererTests.swift
import XCTest
@testable import Shared

final class MarkdownRendererTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

    let renderer = MarkdownRenderer()
    let config = AppConfig()

    func testRendersMarkdownInTemplate() {
        let md = "# Hello World\n\nSome **bold** text."
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("class=\"markdown\""))
        XCTAssertTrue(html.contains("# Hello World"))
        XCTAssertTrue(html.contains("marked v15"), "marked.js source not inlined")
    }

    func testContainsMarkedParseScript() {
        let md = "test"
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("marked.parse"))
    }

    func testContainsKaTeXRenderScript() {
        let md = "Inline $E=mc^2$ math"
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("renderMathInElement") || html.contains("katex"))
    }

    func testEscapesContentForJavaScript() {
        let md = "line with `backtick` and \\ backslash and 'quote'"
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("\\\\"))
    }

    func testDoesNotCloseScriptElement() {
        let md = "</script><img src=x>"
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertFalse(html.contains("</script><img"))
        XCTAssertFalse(html.contains("</SCRIPT><img"))
    }

    func testDoesNotRewriteScriptureWord() {
        let md = "read </scripture> later"
        let html = renderer.render(content: md, config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("</scripture>"))
    }

    // MARK: - Document formatting

    /// The template opens with `* { margin: 0; padding: 0 }`. Before these
    /// rules existed only `.markdown-cell` (the notebook path) restored block
    /// spacing, so a standalone .md file rendered with every heading,
    /// paragraph and list run together and lists with no indent at all.
    func testRestoresBlockSpacingForMarkdownBody() {
        let html = renderer.render(content: "# H\n\ntext", config: config, fileExtension: "md", nonce: nonce)
        for selector in [".markdown h1", ".markdown p", ".markdown ul", ".markdown blockquote"] {
            XCTAssertTrue(html.contains(selector), "no rule for \(selector)")
        }
    }

    func testIndentsListsPastTheBullet() {
        let html = renderer.render(content: "- a\n- b", config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains(".markdown ul, .markdown ol, .markdown-cell ul, .markdown-cell ol"))
        XCTAssertTrue(html.contains("padding-left: 2em"))
    }

    /// PlainTextRenderer honours fontFamily/fontSize/lineHeight; markdown
    /// ignored all three and always rendered at the template's own defaults.
    func testAppliesConfiguredFont() {
        var fontConfig = AppConfig()
        fontConfig.fileTypes = ["md": FileTypeConfig(fontFamily: "Iowan Old Style", fontSize: 18, lineHeight: 1.8)]
        let html = renderer.render(content: "text", config: fontConfig, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("Iowan Old Style"))
        XCTAssertTrue(html.contains("font-size: 18px"))
        XCTAssertTrue(html.contains("line-height: 1.8"))
    }

    /// The global default family is "SF Mono", picked for plain text and code.
    /// Prose must not inherit it, or every markdown document silently renders
    /// monospace without anyone choosing that.
    func testDoesNotInheritTheGlobalMonospaceFamilyForProse() {
        var fontConfig = AppConfig()
        fontConfig.global.fontFamily = "SF Mono"
        let html = renderer.render(content: "text", config: fontConfig, fileExtension: "md", nonce: nonce)
        XCTAssertFalse(
            html.contains("body.markdown {\n    font-family:"),
            "global monospace family leaked into the markdown body"
        )
    }

    /// Size and line height are not family: those always follow the config,
    /// global value included.
    func testAppliesGlobalSizeAndLineHeight() {
        var fontConfig = AppConfig()
        fontConfig.global.fontSize = 17
        fontConfig.global.lineHeight = 1.9
        let html = renderer.render(content: "text", config: fontConfig, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("font-size: 17px"))
        XCTAssertTrue(html.contains("line-height: 1.9"))
    }

    /// The payload stays in the document either way -- correctly escaped it is
    /// just inert text inside the string literal -- so the assertion is about
    /// the quote, which is what would end that literal and let the rest parse
    /// as CSS.
    func testEscapesFontFamilyForCSS() {
        var fontConfig = AppConfig()
        fontConfig.fileTypes = ["md": FileTypeConfig(fontFamily: "a\"; } body { display: none; } .x {")]
        let html = renderer.render(content: "text", config: fontConfig, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("a\\\"; } body"), "quote was not escaped")
        XCTAssertFalse(html.contains("\"a\"; } body"), "font family broke out of the CSS string")
    }

    /// hljs warns and falls back to no-highlight for a fence language it does
    /// not have, leaving the block silently unstyled. The renderer has to
    /// fall back deliberately and mark what it could not highlight.
    func testHandlesFenceLanguagesTheBundleDoesNotHave() {
        let html = renderer.render(content: "```aynql-unknown\nFROM alpine\n```", config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("hljs.getLanguage"), "no registration check before highlighting")
        XCTAssertTrue(html.contains("highlightAuto"), "no fallback for an unregistered language")
        XCTAssertTrue(html.contains("data-unhighlighted-language"), "unhighlighted blocks are not marked")
    }

    /// The hljs theme styles `.hljs` and `pre code.hljs` as if they were the
    /// outermost container. Inside the template's own `pre` that renders a box
    /// within a box, in a different colour.
    func testFencedCodeDoesNotNestASecondBox() {
        let html = renderer.render(content: "```json\n{}\n```", config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains(".markdown pre code.hljs, .markdown-cell pre code.hljs"))
        XCTAssertTrue(html.contains("background: transparent; padding: 0;"))
    }

    /// Blockquote text is body text, so it must not use the gutter grey.
    func testBlockquoteUsesTheMutedTokenNotTheGutterGrey() {
        let html = renderer.render(content: "> quoted", config: config, fileExtension: "md", nonce: nonce)
        XCTAssertTrue(html.contains("--muted"))
        XCTAssertTrue(html.contains("border-left: 4px solid var(--border); color: var(--muted);"))
    }
}
