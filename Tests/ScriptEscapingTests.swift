// Tests/ScriptEscapingTests.swift
import XCTest
@testable import Shared

/// `PlainTextRenderer` and `MarkdownRenderer` each used to carry their own
/// `escapeForJS`, and only the markdown one neutralised `</script`. These pin
/// the single helper both now share.
final class ScriptEscapingTests: XCTestCase {

    // MARK: - Template literal

    func testTemplateLiteralEscapesBackslashBacktickAndDollar() {
        XCTAssertEqual(ScriptEscaping.forTemplateLiteral("a\\b"), "a\\\\b")
        XCTAssertEqual(ScriptEscaping.forTemplateLiteral("a`b"), "a\\`b")
        XCTAssertEqual(ScriptEscaping.forTemplateLiteral("${x}"), "\\${x}")
    }

    func testTemplateLiteralNeutralisesScriptEnd() {
        let escaped = ScriptEscaping.forTemplateLiteral("</script><img src=x onerror=alert(1)>")
        XCTAssertFalse(escaped.contains("</script"))
        XCTAssertTrue(escaped.contains("<\\/script"))
    }

    func testTemplateLiteralNeutralisesScriptEndRegardlessOfCaseOrSpacing() {
        for payload in ["</SCRIPT>", "</Script >", "</script\t>", "</script/", "</script"] {
            let escaped = ScriptEscaping.forTemplateLiteral(payload)
            XCTAssertFalse(escaped.lowercased().contains("</script"), "not neutralised: \(payload)")
        }
    }

    /// `</scriptable` is not an end tag; nothing should be rewritten.
    func testTemplateLiteralLeavesNonTerminatingSequencesAlone() {
        XCTAssertEqual(ScriptEscaping.forTemplateLiteral("</scriptable"), "</scriptable")
    }

    // MARK: - Single-quoted literal

    func testSingleQuotedLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(ScriptEscaping.forSingleQuotedLiteral("it's"), "it\\'s")
        XCTAssertEqual(ScriptEscaping.forSingleQuotedLiteral("a\\b"), "a\\\\b")
    }

    /// A single-quoted literal cannot span lines: an unescaped newline is a
    /// syntax error, which takes the whole inline script down with it.
    func testSingleQuotedLiteralEscapesLineTerminators() {
        XCTAssertEqual(ScriptEscaping.forSingleQuotedLiteral("a\nb"), "a\\nb")
        XCTAssertEqual(ScriptEscaping.forSingleQuotedLiteral("a\r\nb"), "a\\nb")
    }

    func testSingleQuotedLiteralNeutralisesScriptEnd() {
        let escaped = ScriptEscaping.forSingleQuotedLiteral("xml'});</script><img src=x onerror=alert(1)>")
        XCTAssertEqual(escaped, "xml\\'});<\\/script><img src=x onerror=alert(1)>")
    }

    // MARK: - Both renderers go through it

    // These assert that the payload's `</script` was rewritten *in place* —
    // counting script elements in the whole document would count the ones the
    // bundled libraries mention in their own source. Whether the payload is
    // actually inert in a loaded document is asserted behaviourally in
    // `PreviewWebViewLiveTests`.

    func testPlainTextSyntaxHighlightPathNeutralisesScriptEnd() {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "xml")]
        let html = PlainTextRenderer().render(
            content: "</script><img src=x onerror=alert(1)>",
            config: config,
            fileExtension: "txt"
        )
        XCTAssertTrue(html.contains("<\\/script><img src=x onerror=alert(1)>"))
        XCTAssertFalse(html.contains("</script><img"), "the payload ended the script element")
    }

    func testPlainTextSyntaxLanguageCannotBreakOutOfItsLiteral() {
        var config = AppConfig()
        config.fileTypes = [
            "txt": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "xml' });</script><img src=x>")
        ]
        let html = PlainTextRenderer().render(content: "hello", config: config, fileExtension: "txt")
        XCTAssertTrue(html.contains("language: 'xml\\' });<\\/script><img src=x>'"))
        XCTAssertFalse(html.contains("</script><img"), "the language ended the script element")
        XCTAssertFalse(html.contains("class=\"language-xml' });</script>"),
                       "the language reached the class attribute unescaped")
    }

    func testMarkdownNeutralisesScriptEnd() {
        let html = MarkdownRenderer().render(
            content: "</script><img src=x onerror=alert(1)>",
            config: AppConfig(),
            fileExtension: "md"
        )
        XCTAssertTrue(html.contains("<\\/script><img src=x onerror=alert(1)>"))
        XCTAssertFalse(html.contains("</script><img"))
    }
}
