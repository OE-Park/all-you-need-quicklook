// Tests/PreviewWebViewLiveTests.swift
import XCTest
import WebKit
@testable import Shared

/// Behavioural cover for the two things this project could previously get
/// silently wrong: previews running with **no** Content Security Policy at all,
/// and the bundled libraries never executing.
///
/// Both are only observable in a document WebKit has actually loaded, so these
/// tests load one through the real `PreviewWebView` and interrogate it with
/// `evaluateJavaScript`. Nothing here asserts on the shape of the Swift or JS
/// source; `PreviewWebViewCSPTests` covers the policy string itself.
@MainActor
final class PreviewWebViewLiveTests: XCTestCase {

    // MARK: - The policy is installed

    func testPolicyIsInstalledInTheLoadedDocument() throws {
        let nonce = PreviewWebView.makeNonce()
        let web = load("<!DOCTYPE html><html><head></head><body>x</body></html>", nonce: nonce)
        let contents = try evaluateJSON(
            """
            Array.prototype.map.call(
                document.querySelectorAll('meta[http-equiv="Content-Security-Policy" i]'),
                function(m) { return m.content; }
            )
            """,
            in: web
        )
        XCTAssertFalse(contents.isEmpty, "the document loaded with no Content Security Policy at all")
        for content in contents {
            XCTAssertEqual(content, PreviewWebView.contentSecurityPolicy(nonce: nonce))
        }
    }

    // MARK: - The policy is enforced

    /// Network-independent proof that the policy is live rather than merely
    /// present: `script-src` names no `'unsafe-eval'`, so `eval` must throw.
    func testPolicyRefusesEval() throws {
        let web = loadComposed { nonce in
            """
            <!DOCTYPE html><html><head></head><body>
            <script nonce="\(nonce)">
            try { eval('window.__evaled = 1;'); } catch (e) { window.__evalThrew = e.name; }
            </script>
            </body></html>
            """
        }
        XCTAssertEqual(try evaluateString("String(typeof window.__evaled)", in: web), "undefined",
                       "eval() ran despite script-src naming no 'unsafe-eval'")
        XCTAssertEqual(try evaluateString("String(window.__evalThrew)", in: web), "EvalError")
    }

    /// An off-origin `<script src>` that would define a global. The policy
    /// names no host or scheme source for script, so it must never run.
    func testPolicyRefusesOffOriginScript() throws {
        let web = load(
            """
            <!DOCTYPE html><html><head>
            <script src="https://cdn.jsdelivr.net/npm/jquery@3/dist/jquery.min.js"></script>
            </head><body>x</body></html>
            """,
            nonce: PreviewWebView.makeNonce()
        )
        XCTAssertEqual(try evaluateString("String(typeof window.jQuery)", in: web), "undefined",
                       "an off-origin script defined a global")
    }

    /// An off-origin stylesheet must not reach the document either.
    func testPolicyRefusesOffOriginStylesheet() throws {
        let web = load(
            """
            <!DOCTYPE html><html><head>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5/dist/css/bootstrap.min.css">
            </head><body>x</body></html>
            """,
            nonce: PreviewWebView.makeNonce()
        )
        XCTAssertEqual(try evaluateString("String(document.styleSheets.length)", in: web), "0",
                       "an off-origin stylesheet reached the document")
    }

    // MARK: - The bundled libraries run

    func testBundledLibrariesRunInTheLoadedDocument() throws {
        let web = loadComposed { HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: $0) }
        XCTAssertEqual(try evaluateString("typeof marked", in: web), "object")
        XCTAssertEqual(try evaluateString("typeof hljs", in: web), "object")
        XCTAssertEqual(try evaluateString("typeof katex", in: web), "object")
    }

    func testBundledStylesheetsApplyInTheLoadedDocument() throws {
        let web = loadComposed { HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: $0) }
        // App CSS, KaTeX, and the light/dark highlight.js themes.
        XCTAssertEqual(try evaluateString("String(document.styleSheets.length)", in: web), "4")
        XCTAssertEqual(
            try evaluateString(
                "String(Array.prototype.every.call(document.styleSheets, function(s) { return s.cssRules.length > 0; }))",
                in: web
            ),
            "true",
            "a bundled stylesheet loaded but parsed to no rules"
        )
    }

    // MARK: - Rendered markdown

    /// marked removed its `highlight` option in v5 while the bundled build is
    /// v15, so `setOptions({ highlight: … })` was silently ignored and fences
    /// rendered unhighlighted. Asserts the composed document really produces
    /// hljs-classed spans, not that some option was set.
    func testMarkdownFencedCodeBlockIsSyntaxHighlighted() throws {
        let web = loadMarkdown("```python\nimport numpy as np\ndef f(n):\n    return n\n```")
        XCTAssertEqual(
            try evaluateString("String(document.querySelectorAll('#markdown-content pre code.hljs').length)", in: web),
            "1",
            "the fenced block was not handed to highlight.js"
        )
        let spans = try evaluateString(
            "String(document.querySelectorAll('#markdown-content pre code [class^=\"hljs-\"]').length)",
            in: web
        )
        XCTAssertNotEqual(spans, "0", "highlight.js produced no highlighted tokens")
    }

    /// Highlighting must not reintroduce raw source into the DOM: the escaped
    /// `<` and `&` have to survive as text, not become markup.
    func testSyntaxHighlightingDoesNotUnescapeSource() throws {
        let web = loadMarkdown("```python\nif a < b and c > d:\n    pass\n```")
        XCTAssertEqual(
            try evaluateString("document.querySelector('#markdown-content pre code').textContent.indexOf('a < b and c > d') >= 0 ? 'yes' : 'no'", in: web),
            "yes"
        )
        XCTAssertEqual(
            try evaluateString("String(document.querySelectorAll('#markdown-content pre code b, #markdown-content pre code i').length)", in: web),
            "0",
            "escaped source was reinterpreted as markup"
        )
    }

    func testMarkdownHeadingsTablesAndMathRender() throws {
        let web = loadMarkdown("# Title\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nInline: $E = mc^2$\n")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content h1').length)", in: web), "1")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content table').length)", in: web), "1")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content .katex').length)", in: web), "1")
        XCTAssertEqual(
            try evaluateString("document.getElementById('markdown-content').textContent.indexOf('$') >= 0 ? 'yes' : 'no'", in: web),
            "no",
            "math was left as $…$ source"
        )
    }

    /// `bundledJS` rewrites `<!--` to `<\x21--`, and in marked.min.js that
    /// sequence sits inside the regex literal that recognises HTML comments.
    /// If the rewrite were not semantics-preserving, comment handling would be
    /// the first thing to break.
    func testEscapingBundledJSDidNotAlterLibraryBehaviour() throws {
        let web = loadMarkdown("before\n\n<!-- hidden comment -->\n\nafter\n")
        let text = try evaluateString("document.getElementById('markdown-content').textContent", in: web)
        XCTAssertTrue(text.contains("before"))
        XCTAssertTrue(text.contains("after"))
        XCTAssertFalse(text.contains("hidden comment"),
                       "marked stopped recognising HTML comments after source escaping")
    }

    // MARK: - A previewed file cannot break out of its script element

    // The syntax-highlight path interpolates the file's own text into a
    // template literal inside an inline `<script>`. Escaping the *literal* is
    // not enough: the HTML tokenizer runs first, so a literal `</script` ends
    // the *element* and the remainder is parsed as markup — which
    // `script-src 'unsafe-inline'` then permits to run. These load the composed
    // document and ask the DOM, rather than grepping the string.

    private static let breakoutPayload =
        "</script><img src=x onerror=\"window.__pwnedByImage = 1\">\n"
        + "<script>window.__pwnedByScript = 1;</script>"

    func testPlainTextCannotBreakOutOfItsScriptElement() throws {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "xml")]
        let web = loadComposed { nonce in
            PlainTextRenderer().render(
                content: Self.breakoutPayload, config: config, fileExtension: "txt", nonce: nonce
            )
        }

        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('img').length)", in: web), "0",
                       "the payload became a live element")
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByImage)", in: web), "undefined")
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByScript)", in: web), "undefined")

        // …and the file still rendered, so the escape did not simply break it.
        XCTAssertTrue(
            try evaluateString("document.getElementById('code-content').textContent", in: web)
                .contains("__pwnedByImage"),
            "the file's text did not reach the page at all"
        )
    }

    /// The language comes from the config the Settings tab writes, and lands in
    /// a single-quoted literal in the same inline script.
    func testPlainTextSyntaxLanguageCannotBreakOutOfItsScriptElement() throws {
        var config = AppConfig()
        config.fileTypes = [
            "txt": FileTypeConfig(
                syntaxHighlight: true,
                syntaxLanguage: "xml' });</script><img src=x onerror=\"window.__pwnedByLanguage = 1\">"
            )
        ]
        let web = loadComposed { nonce in
            PlainTextRenderer().render(
                content: "hello", config: config, fileExtension: "txt", nonce: nonce
            )
        }

        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('img').length)", in: web), "0")
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByLanguage)", in: web), "undefined")
    }

    /// Markdown's raw HTML is a separate matter: marked has had no sanitizer
    /// since v5 and the bundled build is v15, so `<img onerror>` in a `.md`
    /// file still reaches the DOM — it is `script-src 'nonce-…'` that keeps it
    /// from firing, which the next section asserts. What the *escape* has to
    /// guarantee is narrower: that the payload arrives as marked's output
    /// *inside* the container, rather than as document-level markup that ended
    /// the script element early.
    func testMarkdownPayloadArrivesThroughMarkedRatherThanByEndingTheScript() throws {
        let web = loadMarkdown(Self.breakoutPayload)
        XCTAssertEqual(
            try evaluateString("String(document.querySelectorAll('body > img, head img').length)", in: web),
            "0",
            "the payload ended the script element and was parsed as document markup"
        )
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByScript)", in: web), "undefined",
                       "an injected <script> element ran")
    }

    // MARK: - A previewed file's own scripts are inert under the nonce policy

    /// Both shapes a `.md` file has: an inline event handler — which ran under
    /// `script-src 'unsafe-inline'` — and a bare `<script>` element. Neither
    /// may run, while the bundled libraries, which do carry this load's nonce,
    /// must still do their work in the very same document. A nonce that broke
    /// our own libraries would pass the first half of this test and fail the
    /// second.
    func testMarkdownFileScriptsAreInertWhileBundledLibrariesStillRun() throws {
        let web = loadMarkdown(
            """
            # Heading

            <img src=x onerror="window.__pwnedByImage = 1">
            <svg><animate onbegin="window.__pwnedBySvg = 1" attributeName="x" dur="1s"></svg>
            <script>window.__pwnedByScript = 1;</script>

            | A | B |
            |---|---|
            | 1 | 2 |

            ```python
            def f(n):
                return n
            ```

            Inline: $E = mc^2$
            """
        )

        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByImage)", in: web), "undefined",
                       "an inline onerror handler ran")
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedBySvg)", in: web), "undefined",
                       "an inline SVG onbegin handler ran")
        XCTAssertEqual(try evaluateString("String(typeof window.__pwnedByScript)", in: web), "undefined",
                       "an inline <script> from the file ran")

        // …and the document is not merely blank: everything nonced still ran.
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content h1').length)", in: web), "1")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content table').length)", in: web), "1")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('#markdown-content .katex').length)", in: web), "1")
        XCTAssertNotEqual(
            try evaluateString(
                "String(document.querySelectorAll('#markdown-content pre code [class^=\"hljs-\"]').length)",
                in: web
            ),
            "0",
            "the nonce blocked highlight.js as well as the payload"
        )
    }

    /// The notebook path is the one that actually needed this.
    /// `NotebookRenderer.renderMimeData` hands a cell's `text/html` output to
    /// the parser as document markup, so a bare `<script>` in a notebook output
    /// was a real script element and ran — no `innerHTML` inertness, no
    /// `onerror` trick required. Only the nonce stops it.
    func testNotebookHTMLOutputScriptsAreInertWhileBundledLibrariesStillRun() throws {
        let web = loadNotebook(
            """
            {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[
            {"cell_type":"markdown","metadata":{},"source":["# Notebook\\n","\\n","$E = mc^2$"]},
            {"cell_type":"code","metadata":{},"source":["import numpy as np"],"execution_count":1,
             "outputs":[{"output_type":"execute_result","execution_count":1,"metadata":{},"data":{"text/html":[
               "<div>chart</div>",
               "<script>window.__notebookInlineScript = 1;<\\/script>",
               "<img src=x onerror=\\"window.__notebookHandler = 1\\">"
             ]}}]}
            ]}
            """
        )

        XCTAssertEqual(try evaluateString("String(typeof window.__notebookInlineScript)", in: web), "undefined",
                       "a bare <script> in a notebook text/html output ran")
        XCTAssertEqual(try evaluateString("String(typeof window.__notebookHandler)", in: web), "undefined",
                       "an inline onerror handler in a notebook text/html output ran")

        // The output itself is still shown, with a notice in place of the
        // chart the script would have drawn.
        XCTAssertEqual(
            try evaluateString("document.body.textContent.indexOf('chart') >= 0 ? 'yes' : 'no'", in: web),
            "yes"
        )
        XCTAssertEqual(
            try evaluateString(
                "String(document.querySelectorAll('.cell-output .placeholder-image').length)", in: web
            ),
            "1",
            "no notice was shown where the blocked script's output would have been"
        )

        // …and the rest of the notebook rendered.
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('.markdown-cell h1').length)", in: web), "1")
        XCTAssertEqual(try evaluateString("String(document.querySelectorAll('.markdown-cell .katex').length)", in: web), "1")
        XCTAssertNotEqual(
            try evaluateString("String(document.querySelectorAll('.code-source [class^=\"hljs-\"]').length)", in: web),
            "0",
            "the nonce blocked highlight.js in the notebook document"
        )
    }

    /// Rotation, on one web view, across two loads: the second document's
    /// nonce differs from the first's, and a document still carrying the first
    /// nonce is refused after the second load has re-armed the policy. Without
    /// `removeAllUserScripts()` the old `<meta>` would keep being injected and
    /// the stale nonce would stay live forever.
    func testEachLoadRotatesTheNonceAndAStaleOneIsRefused() throws {
        func probe(_ nonce: String) -> String {
            "<!DOCTYPE html><html><head></head><body>"
            + "<script nonce=\"\(nonce)\">window.__ran = 1;</script></body></html>"
        }

        let web = PreviewWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        let first = PreviewWebView.makeNonce()
        load(probe(first), nonce: first, into: web)
        XCTAssertEqual(web.installedNonce, first)
        XCTAssertEqual(try evaluateString("String(typeof window.__ran)", in: web), "number",
                       "the document's own nonced script did not run")

        let second = PreviewWebView.makeNonce()
        XCTAssertNotEqual(second, first)
        load(probe(second), nonce: second, into: web)
        XCTAssertEqual(web.installedNonce, second, "the nonce was not rotated")
        XCTAssertEqual(try evaluateString("String(typeof window.__ran)", in: web), "number")

        // Third load: the policy is armed with a third nonce, and the document
        // presents the first one.
        let third = PreviewWebView.makeNonce()
        load(probe(first), nonce: third, into: web)
        XCTAssertEqual(web.installedNonce, third)
        XCTAssertEqual(try evaluateString("String(typeof window.__ran)", in: web), "undefined",
                       "a previous load's nonce was still accepted")
    }

    // MARK: - Helpers

    private func loadMarkdown(_ markdown: String) -> PreviewWebView {
        loadComposed { nonce in
            MarkdownRenderer().render(
                content: markdown, config: AppConfig(), fileExtension: "md", nonce: nonce
            )
        }
    }

    private func loadNotebook(_ json: String) -> PreviewWebView {
        loadComposed { nonce in
            NotebookRenderer().render(
                content: json, config: AppConfig(), fileExtension: "ipynb", nonce: nonce
            )
        }
    }

    /// Composes a document with a fresh nonce and loads it with the same one.
    ///
    /// Passing the nonce to only one of the two halves is the mistake this
    /// whole change makes possible, so no helper here lets it happen.
    private func loadComposed(_ compose: (String) -> String) -> PreviewWebView {
        let nonce = PreviewWebView.makeNonce()
        return load(compose(nonce), nonce: nonce)
    }

    @discardableResult
    private func load(_ html: String, nonce: String) -> PreviewWebView {
        load(html, nonce: nonce, into: PreviewWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    @discardableResult
    private func load(_ html: String, nonce: String, into web: PreviewWebView) -> PreviewWebView {
        let finished = expectation(description: "navigation finished")
        let delegate = LoadDelegate { finished.fulfill() }
        loadDelegates.append(delegate)
        web.navigationDelegate = delegate
        web.loadHTML(html, resourcesURL: nil, nonce: nonce)
        wait(for: [finished], timeout: 60)
        return web
    }

    /// `evaluateJavaScript` cannot marshal `undefined`, so every expression is
    /// forced to a string on the JS side.
    private func evaluateString(
        _ expression: String,
        in web: PreviewWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let finished = expectation(description: "evaluated")
        var result: Any?
        var failure: Error?
        web.evaluateJavaScript("String(\(expression))") { value, error in
            result = value
            failure = error
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
        if let failure { throw failure }
        return try XCTUnwrap(result as? String, "not a string: \(expression)", file: file, line: line)
    }

    private func evaluateJSON(
        _ expression: String,
        in web: PreviewWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String] {
        let json = try evaluateString("JSON.stringify(\(expression))", in: web, file: file, line: line)
        let data = try XCTUnwrap(json.data(using: .utf8), file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String],
            "not an array of strings: \(json)",
            file: file,
            line: line
        )
    }

    /// Navigation delegates are held weakly by WKWebView; keep them alive for
    /// the duration of the test.
    private var loadDelegates: [LoadDelegate] = []
}

private final class LoadDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinish() }
}
