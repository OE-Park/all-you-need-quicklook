// Shared/WebView/PreviewWebView.swift
import WebKit

public final class PreviewWebView: WKWebView {

    private let imageTimeoutSeconds: TimeInterval

    public init(frame: CGRect = .zero, imageTimeoutSeconds: TimeInterval = 3) {
        self.imageTimeoutSeconds = imageTimeoutSeconds

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let contentController = WKUserContentController()
        // Content Security Policy: only allow inline scripts (our bundled JS is
        // loaded via <script src> from local baseURL), inline styles, and images
        // from data: URIs and HTTP/HTTPS. Blocks external JS/CSS/iframes.
        let cspScript = WKUserScript(
            source: """
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' blob:; img-src data: http: https:; font-src data:;";
            document.head.prepend(meta);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(cspScript)
        config.userContentController = contentController

        super.init(frame: frame, configuration: config)

        self.navigationDelegate = self
        self.setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func loadHTML(_ html: String, resourcesURL: URL?) {
        if let baseURL = resourcesURL {
            loadHTMLString(html, baseURL: baseURL)
        } else {
            loadHTMLString(html, baseURL: nil)
        }
    }
}

extension PreviewWebView: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Allow initial HTML load and same-document navigation (anchors)
        if navigationAction.navigationType == .other {
            return .allow
        }
        // Block all user-initiated navigation (link clicks, form submissions, etc.)
        return .cancel
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        .allow
    }
}
