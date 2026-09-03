import WebKit
import XCTest
@testable import Shared

@MainActor
final class PreviewWebViewIntegrationTests: XCTestCase {

    func testMarkdownLoadsBundledLibrariesAndRendersWithoutActivatingRawHTML() async throws {
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
            fileExtension: "md"
        )
        let webView = PreviewWebView()

        webView.loadHTML(html, resourcesURL: try resourcesURL())

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
        XCTAssertEqual(rawElementExists, false)
        XCTAssertEqual(handlerRan, false)
    }

    func testFailedExternalImageBecomesPlaceholder() async throws {
        let html = HTMLTemplate.wrap(
            body: "<img id=\"external\" src=\"https://127.0.0.1:1/missing.png\">",
            rendererType: "markdown"
        )
        let webView = PreviewWebView(imageTimeoutSeconds: 0.2)

        webView.loadHTML(html, resourcesURL: try resourcesURL())

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
            rendererType: "markdown"
        )
        let webView = PreviewWebView()
        webView.loadHTML(html, resourcesURL: try resourcesURL())
        try await waitUntilTrue(
            in: webView,
            expression: "document.documentElement.dataset.quicklookReady === 'true'"
        )

        _ = try? await webView.evaluateJavaScript("document.getElementById('jump').click()")
        try await waitUntilTrue(in: webView, expression: "location.hash === '#target'")

        _ = try? await webView.evaluateJavaScript("location.href = 'https://example.com/escaped'")
        try await Task.sleep(for: .milliseconds(200))
        let stayedLocal = try await webView.evaluateJavaScript(
            "location.protocol === 'quicklook-resource:' && document.getElementById('target') !== null"
        ) as? Bool

        XCTAssertEqual(stayedLocal, true)
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
