// Shared/WebView/PreviewWebView.swift
import WebKit

public final class PreviewWebView: WKWebView {

    /// Content Security Policy applied to every preview document.
    ///
    /// The policy is deliberately inline-only for script and style: the preview
    /// is handed to WebKit through `loadHTMLString(_:baseURL:)`, whose document
    /// gets an opaque origin and cannot load *any* subresource from the file://
    /// `baseURL` — not with `'self'`, not with a `file:` source. `HTMLTemplate`
    /// therefore inlines the bundled libraries (marked.js, highlight.js, KaTeX)
    /// directly into the document, and this policy admits exactly that while
    /// still refusing third-party script, style, frames and everything else that
    /// `default-src 'none'` covers.
    ///
    /// `img-src` keeps http/https because remote images in Markdown and notebook
    /// output are a deliberate, spec-required allowance; `font-src data:` keeps
    /// fonts to embedded data URIs only.
    ///
    /// Must contain no `"` or `\` — it is interpolated into a JS string literal
    /// by `cspUserScriptSource`.
    public nonisolated static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' blob:; "
        + "img-src data: http: https:; font-src data:;"

    /// Installs `contentSecurityPolicy` as a `<meta http-equiv>` before the
    /// document's own markup is parsed.
    ///
    /// At `.atDocumentStart` for a `loadHTMLString` load, `document.head` is
    /// still `null` — only `document.documentElement` exists. Reaching straight
    /// for `document.head` throws, and a throw here leaves the document with
    /// *no* policy at all rather than a loud failure, so every node this walks
    /// is created when it is missing instead of being dereferenced on faith.
    /// `PreviewWebViewLiveTests` asserts the meta really lands in a loaded
    /// document; this comment is not the guarantee, that test is.
    nonisolated static var cspUserScriptSource: String {
        """
        (function() {
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "\(contentSecurityPolicy)";
            var root = document.documentElement;
            if (!root) {
                root = document.createElement('html');
                document.appendChild(root);
            }
            var head = document.head;
            if (!head) {
                head = document.createElement('head');
                root.prepend(head);
            }
            head.prepend(meta);
        })();
        """
    }

    private let imageTimeoutSeconds: TimeInterval

    public init(frame: CGRect = .zero, imageTimeoutSeconds: TimeInterval = 3) {
        self.imageTimeoutSeconds = imageTimeoutSeconds

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let contentController = WKUserContentController()
        let cspScript = WKUserScript(
            source: Self.cspUserScriptSource,
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
