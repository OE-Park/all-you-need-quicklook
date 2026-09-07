import WebKit
import XCTest
@testable import Shared

@MainActor
final class PreviewWebViewIntegrationTests: XCTestCase {
    private let nonce = PreviewWebView.makeNonce()

    func testMarkdownLoadsBundledLibrariesAndRendersWithoutExecutingRawHTMLHandlers() async throws {
        let renderer = MarkdownRenderer()
        let html = renderer.render(
            content: """
            # Hello

            ```swift
            let value = 1
            ```

            Inline math: $E=mc^2$

            <img id="raw-html" src="x" onerror="globalThis.pwned = true">
            """,
            config: AppConfig(),
            fileExtension: "md", nonce: nonce
        )
        let webView = PreviewWebView()

        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)

        try await waitUntilTrue(
            in: webView,
            expression: """
            document.readyState === 'complete' &&
            document.querySelector('h1')?.textContent === 'Hello' &&
            document.querySelector('pre code')?.classList.contains('hljs') === true &&
            document.querySelector('.katex') !== null
            """
        )
        let libraries = try await webView.evaluateJavaScript(
            "[typeof marked, typeof hljs, typeof katex].join(',')"
        ) as? String
        let rawElementExists = try await webView.evaluateJavaScript(
            "document.getElementById('raw-html') !== null"
        ) as? Bool
        let handlerRan = try await webView.evaluateJavaScript(
            "globalThis.pwned === true"
        ) as? Bool

        XCTAssertEqual(libraries, "object,object,object")
        XCTAssertEqual(rawElementExists, true)
        XCTAssertEqual(handlerRan, false)
    }

    func testFailedExternalImageBecomesPlaceholder() async throws {
        let html = HTMLTemplate.wrap(
            body: "<img id=\"external\" src=\"https://127.0.0.1:1/missing.png\">",
            rendererType: "markdown", nonce: nonce
        )
        let webView = PreviewWebView(imageTimeoutSeconds: 0.2)

        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)

        try await waitUntilTrue(
            in: webView,
            expression: "document.querySelector('.placeholder-image') !== null"
        )
        let externalImageExists = try await webView.evaluateJavaScript(
            "document.getElementById('external') !== null"
        ) as? Bool

        XCTAssertEqual(externalImageExists, false)
    }

    func testAllowsAnchorButBlocksProgrammaticExternalNavigation() async throws {
        let html = HTMLTemplate.wrap(
            body: "<a id=\"jump\" href=\"#target\">jump</a><div id=\"target\">target</div>",
            rendererType: "markdown", nonce: nonce
        )
        let webView = PreviewWebView()
        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)
        try await waitUntilTrue(
            in: webView,
            expression: "document.documentElement.dataset.quicklookReady === 'true'"
        )

        _ = try? await webView.evaluateJavaScript("document.getElementById('jump').click()")
        try await waitUntilTrue(in: webView, expression: "location.hash === '#target'")

        _ = try? await webView.evaluateJavaScript("location.href = 'https://example.com/escaped'")
        try await Task.sleep(for: .milliseconds(200))
        let stayedLocal = try await webView.evaluateJavaScript(
            "location.protocol === 'file:' && document.getElementById('target') !== null"
        ) as? Bool

        XCTAssertEqual(stayedLocal, true)
    }

    func testMalformedAnchorDoesNotRaiseJavaScriptError() async throws {
        let html = HTMLTemplate.wrap(
            body: """
            <script nonce="\(nonce)">
            globalThis.anchorErrors = 0;
            window.addEventListener('error', function() { globalThis.anchorErrors += 1; });
            </script>
            <a id="malformed" href="#%E0%A4%A">malformed</a>
            """,
            rendererType: "markdown", nonce: nonce
        )
        let webView = PreviewWebView()
        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)
        try await waitUntilTrue(
            in: webView,
            expression: "document.documentElement.dataset.quicklookReady === 'true'"
        )

        _ = try? await webView.evaluateJavaScript("document.getElementById('malformed').click()")
        try await Task.sleep(for: .milliseconds(100))
        let errorCount = try await webView.evaluateJavaScript("globalThis.anchorErrors") as? Int

        XCTAssertEqual(errorCount, 0)
    }

    func testUnknownSyntaxLanguageStillRendersPlainTextContent() async throws {
        var config = AppConfig()
        config.fileTypes = [
            "txt": FileTypeConfig(
                syntaxHighlight: true,
                syntaxLanguage: "not-a-highlight-language"
            )
        ]
        let html = PlainTextRenderer().render(
            content: "visible fallback content",
            config: config,
            fileExtension: "txt", nonce: nonce
        )
        let webView = PreviewWebView()
        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)

        try await waitUntilTrue(
            in: webView,
            expression: "document.getElementById('code-content')?.textContent === 'visible fallback content'"
        )
    }

    func testCSPBlocksResourceSchemeFromDifferentHost() async throws {
        let handler = CSPProbeSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "quicklook-resource")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let html = HTMLTemplate.wrap(
            body: """
            <link rel="stylesheet" href="quicklook-resource://bundle/probe.css">
            <div id="csp-probe">probe</div>
            <script src="quicklook-resource://untrusted/payload.js"></script>
            """,
            rendererType: "markdown", nonce: nonce
        )

        webView.loadHTMLString(
            html,
            baseURL: URL(string: "quicklook-resource://bundle/")
        )

        try await waitUntilTrue(
            in: webView,
            expression: """
            document.documentElement.dataset.quicklookReady === 'true'
            """
        )
        let crossOriginScriptRan = try await webView.evaluateJavaScript(
            "globalThis.crossOriginScriptRan === true"
        ) as? Bool

        XCTAssertEqual(crossOriginScriptRan, false)
    }

    private func resourcesURL() throws -> URL {
        try XCTUnwrap(Bundle(for: ConfigLoader.self).resourceURL)
    }

    private func waitUntilTrue(
        in webView: WKWebView,
        expression: String,
        attempts: Int = 100
    ) async throws {
        for _ in 0..<attempts {
            if let value = try? await webView.evaluateJavaScript(expression) as? Bool,
               value {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let diagnostics = (try? await webView.evaluateJavaScript(
            """
            JSON.stringify({
                readyState: document.readyState,
                url: document.URL,
                baseURI: document.baseURI,
                csp: document.querySelector('meta[http-equiv="Content-Security-Policy"]')?.content,
                scripts: Array.from(document.scripts).map(function(script) {
                    return { src: script.src, nonce: script.nonce, inlineLength: script.text.length };
                }),
                marked: typeof marked,
                quicklookReady: document.documentElement.dataset.quicklookReady || null
            })
            """
        ) as? String) ?? "unavailable"
        XCTFail("Timed out waiting for JavaScript expression: \(expression)\nDiagnostics: \(diagnostics)")
    }
}

private final class CSPProbeSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let isStylesheet = url.pathExtension.lowercased() == "css"
        let source = isStylesheet
            ? "#csp-probe { color: rgb(1, 2, 3); }"
            : url.host == "untrusted" ? "globalThis.crossOriginScriptRan = true;" : ""
        let data = Data(source.utf8)
        let response = URLResponse(
            url: url,
            mimeType: isStylesheet ? "text/css" : "text/javascript",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
