import ImageIO
import Network
import UniformTypeIdentifiers
import WebKit
import XCTest
@testable import Shared

@MainActor
final class PreviewWebViewIntegrationTests: XCTestCase {
    private let nonce = PreviewWebView.makeNonce()
    /// Keeps the probe's web view alive for the whole test.
    private var remoteImageWebView: PreviewWebView?

    func testMarkdownLoadsBundledLibrariesAndRendersWithoutExecutingRawHTMLHandlers() async throws {
        let renderer = MarkdownRenderer()
        let html = renderer.render(
            content: """
            # Hello

            ```swift
            let value = 1
            ```

            Inline math: $E=mc^2$

            <img id="raw-html" src="data:," onerror="globalThis.pwned = true">
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
            rendererType: "markdown", nonce: nonce, allowExternalImages: true
        )
        let webView = PreviewWebView(imageTimeoutSeconds: 0.2, allowExternalImages: true)

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

    func testRemoteImageIsRefusedByPolicyWhenOff() async throws {
        let html = HTMLTemplate.wrap(
            body: """
            <script nonce="\(nonce)">
            globalThis.violations = [];
            document.addEventListener('securitypolicyviolation', function(event) {
                globalThis.violations.push(event.blockedURI);
            });
            </script>
            <img src="https://example.test/x.png">
            """,
            rendererType: "markdown", nonce: nonce, allowExternalImages: false
        )
        let webView = PreviewWebView(allowExternalImages: false)

        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)

        try await waitUntilTrue(
            in: webView,
            expression: "globalThis.violations.some(function(uri) { return uri.indexOf('https://example.test') === 0; })"
        )
    }

    /// Spec: with images off the CSP refuses the remote image and no request
    /// reaches the host. Counting accepted connections on a loopback listener
    /// proves the second half; the paired control proves the probe can see a
    /// connection at all, so a zero is not vacuous.
    func testRemoteImageSendsNoRequestWhenOff() async throws {
        let silent = try await SilentListener.start()
        defer { silent.stop() }

        try await loadRemoteImage(allowExternalImages: false, port: silent.port)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(silent.connectionCount, 0, "a remote image request reached the server with images off")
    }

    func testLegacyImagesOnSendsNoRequestUntilByteLimitCanBeEnforced() async throws {
        let silent = try await SilentListener.start()
        defer { silent.stop() }

        try await loadRemoteImage(allowExternalImages: true, port: silent.port)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(silent.connectionCount, 0, "legacy opt-in bypassed the response-size policy")
    }

    func testResponsiveAndLazyRemoteImagesAreBlockedWithoutRequests() async throws {
        let silent = try await SilentListener.start()
        defer { silent.stop() }
        let url = "http://127.0.0.1:\(silent.port)/large.png"
        let html = HTMLTemplate.wrap(body: """
            <img srcset="\(url) 1x">
            <picture><source srcset="\(url) 1x"><img src="data:image/png;base64,aA=="></picture>
            <img loading="lazy" style="margin-top:10000px" src="\(url)">
            """, rendererType: "markdown", nonce: nonce, allowExternalImages: true)
        let web = PreviewWebView(allowExternalImages: true)
        web.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)
        try await waitUntilTrue(in: web, expression: "document.querySelectorAll('.external-image-blocked').length === 3")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(silent.connectionCount, 0)
    }

    private func loadRemoteImage(allowExternalImages: Bool, port: UInt16) async throws {
        let html = HTMLTemplate.wrap(
            body: "<img src=\"http://127.0.0.1:\(port)/x.png\">",
            rendererType: "markdown", nonce: nonce,
            allowExternalImages: allowExternalImages, imageTimeoutSeconds: 30
        )
        let webView = PreviewWebView(allowExternalImages: allowExternalImages)
        remoteImageWebView = webView
        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)
        try await waitUntilTrue(
            in: webView,
            expression: "document.documentElement.dataset.quicklookReady === 'true'"
        )
    }

    func testUnansweredRemoteImageIsBlockedBeforeStartingARequest() async throws {
        let silent = try await SilentListener.start()
        defer { silent.stop() }
        let html = HTMLTemplate.wrap(body: "<img src=\"http://127.0.0.1:\(silent.port)/x.png\">",
                                     rendererType: "markdown", nonce: nonce,
                                     allowExternalImages: true, imageTimeoutSeconds: 1)
        let web = PreviewWebView(allowExternalImages: true)
        web.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce)
        try await waitUntilTrue(in: web, expression: "document.querySelector('.external-image-blocked') !== null")
        XCTAssertEqual(silent.connectionCount, 0)
    }

    func testNoQuicklookImageSchemeRemains() {
        for allow in [false, true] {
            let html = HTMLTemplate.wrap(body: "<p>x</p>", rendererType: "markdown", nonce: nonce, allowExternalImages: allow)
            XCTAssertFalse(html.contains("quicklook-image"))
        }
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

    func testRelativeImageRendersThroughLocalScheme() async throws {
        let directory = try makeDocumentDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("pic.png"))
        let html = MarkdownRenderer().render(
            content: "![x](pic.png)", config: AppConfig(), fileExtension: "md", nonce: nonce
        )
        let webView = PreviewWebView()

        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce, documentDirectory: directory)

        try await waitUntilTrue(
            in: webView,
            expression: "document.querySelector('img')?.naturalWidth > 0"
        )
        let src = try await webView.evaluateJavaScript("document.querySelector('img').src") as? String
        XCTAssertEqual(src?.hasPrefix("quicklook-local://image/"), true)
    }

    func testMissingRelativeImageBecomesPlaceholder() async throws {
        let directory = try makeDocumentDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = MarkdownRenderer().render(
            content: "![x](missing.png)", config: AppConfig(), fileExtension: "md", nonce: nonce
        )
        let webView = PreviewWebView()

        webView.loadHTML(html, resourcesURL: try resourcesURL(), nonce: nonce, documentDirectory: directory)

        try await waitUntilTrue(
            in: webView,
            expression: "document.querySelector('.placeholder-image')?.textContent === 'Image unavailable' && document.querySelector('img') === null"
        )
    }

    private func makeDocumentDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("relative-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(_ url: URL) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
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

/// A loopback TCP listener that accepts connections and never replies.
private final class SilentListener: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var accepted = 0

    /// Connections accepted since `start()`; unaffected by `stop()`.
    var connectionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return accepted
    }

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> SilentListener {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "silent-listener")
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready where once.claim():
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error) where once.claim():
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        let silent = SilentListener(listener: listener, port: port)
        listener.newConnectionHandler = { [weak silent] connection in
            guard let silent else { return }
            silent.lock.lock()
            silent.connections.append(connection)
            silent.accepted += 1
            silent.lock.unlock()
            connection.start(queue: queue)   // accepted, then left silent
        }
        return silent
    }

    func stop() {
        listener.cancel()
        lock.lock()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        lock.unlock()
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    /// True only for the first caller.
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { used = true }
        return !used
    }
}
