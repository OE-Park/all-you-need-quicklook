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
    /// fonts to embedded data URIs only. `img-src` is consequently the *only*
    /// outbound channel a previewed file has — see the plan's Security Note.
    ///
    /// `base-uri` and `form-action` are named explicitly because neither falls
    /// back to `default-src`: without them an injected `<base>` or `<form>`
    /// would be unrestricted even under `default-src 'none'`.
    ///
    /// `style-src` no longer names `blob:`. Nothing in this project creates a
    /// blob stylesheet, and an unused source is only ever an unused source in
    /// the attacker's favour.
    ///
    /// Must contain no `"` or `\` — it is interpolated into a JS string literal
    /// by `cspUserScriptSource`.
    public nonisolated static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
        + "img-src data: http: https:; font-src data:; base-uri 'none'; form-action 'none';"

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

    /// The `baseURL` of a load this view itself started, still waiting for its
    /// navigation to be decided.
    ///
    /// `loadHTMLString(_:baseURL:)` reaches the navigation delegate as a
    /// `.other` navigation to that `baseURL`, indistinguishable by type from a
    /// `window.location =` the previewed document performs. Recording the URL
    /// we are expecting — and clearing it the moment it is allowed — is what
    /// lets `decidePolicyFor` tell the two apart.
    private var pendingLoadBaseURL: URL?

    public func loadHTML(_ html: String, resourcesURL: URL?) {
        pendingLoadBaseURL = resourcesURL
        if let baseURL = resourcesURL {
            loadHTMLString(html, baseURL: baseURL)
        } else {
            loadHTMLString(html, baseURL: nil)
        }
    }

    /// Whether a `.other` navigation to `url` is this view's own pending load.
    ///
    /// Compared standardized and without a trailing slash: `resourcesURL` is a
    /// directory URL, and WebKit does not promise to hand the string back
    /// byte-for-byte.
    func consumePendingLoad(of url: URL?) -> Bool {
        guard let pending = pendingLoadBaseURL else { return false }
        guard let url, Self.sameResource(url, pending) else { return false }
        pendingLoadBaseURL = nil
        return true
    }

    private nonisolated static func sameResource(_ lhs: URL, _ rhs: URL) -> Bool {
        func key(_ url: URL) -> String {
            var string = url.standardized.absoluteString
            while string.count > 1, string.hasSuffix("/") { string.removeLast() }
            return string
        }
        return key(lhs) == key(rhs)
    }
}

extension PreviewWebView: WKNavigationDelegate {

    /// Allows this view's own document load and nothing else.
    ///
    /// Gating on `navigationType` alone is not enough. `.other` is the type of
    /// the `loadHTMLString` load, but it is *also* the type of a
    /// `window.location = 'https://…'`, a `<meta http-equiv="refresh">` and a
    /// script-driven `form.submit()` — so allowing every `.other` left the
    /// previewed document free to navigate anywhere it liked, and only the
    /// user-initiated kinds (link clicks) were ever blocked.
    ///
    /// The destination is therefore checked too: `nil` and `about:blank` are
    /// the load with no base URL, and exactly one navigation to the base URL
    /// this view last passed to `loadHTMLString` is admitted. Everything else,
    /// of any type or scheme, is cancelled.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .other else { return .cancel }

        let url = navigationAction.request.url
        if url == nil || url?.absoluteString == "about:blank" { return .allow }
        return consumePendingLoad(of: url) ? .allow : .cancel
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        .allow
    }
}
