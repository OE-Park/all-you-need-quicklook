// Shared/WebView/PreviewWebView.swift
import Foundation
import Security
import WebKit

public final class PreviewWebView: WKWebView {

    /// A fresh, unguessable nonce for one preview document.
    ///
    /// `SecRandomCopyBytes` rather than `UUID()`: it is the platform's
    /// documented cryptographic RNG, whereas `UUID()`'s randomness is an
    /// implementation detail and it spends six of its 128 bits on version and
    /// variant tags. 16 bytes is the length OWASP recommends for a CSP nonce.
    ///
    /// Base64 is chosen for the encoding because its alphabet
    /// (`A-Za-z0-9+/=`) sits inside CSP's `base64-value` grammar *and* inside
    /// what both an HTML attribute value and a JavaScript double-quoted string
    /// literal accept unescaped — so the value can be interpolated into
    /// `contentSecurityPolicy(nonce:)`, into `cspUserScriptSource(nonce:)`'s JS
    /// string and into `HTMLTemplate.wrap`'s `<script nonce="…">` with no
    /// escaping step that could later be forgotten.
    public nonisolated static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        if status != errSecSuccess {
            // Never degrade to a constant. A predictable nonce is worse than
            // `'unsafe-inline'`, because the policy would still read as strict.
            var rng = SystemRandomNumberGenerator()
            bytes = (0..<bytes.count).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        return Data(bytes).base64EncodedString()
    }

    /// Content Security Policy applied to one preview document.
    ///
    /// The policy is deliberately inline-only for style, and nonce-only for
    /// script: the preview is handed to WebKit through
    /// `loadHTMLString(_:baseURL:)`, whose document gets an opaque origin and
    /// cannot load *any* subresource from the file:// `baseURL` — not with
    /// `'self'`, not with a `file:` source. `HTMLTemplate` therefore inlines
    /// the bundled libraries (marked.js, highlight.js, KaTeX) directly into the
    /// document, and this policy admits exactly those `<script>` elements —
    /// the ones stamped with this load's nonce — while refusing every other
    /// inline script, every inline event handler, every `javascript:` URL, and
    /// third-party script, style, frames and the rest that `default-src 'none'`
    /// covers.
    ///
    /// `script-src` names *only* the nonce. No `'unsafe-inline'` (a nonce would
    /// be ignored in its presence by CSP2-era parsers and, more to the point,
    /// it is the thing being removed), no `'strict-dynamic'`, no host.
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
    /// by `cspUserScriptSource(nonce:)`. `makeNonce()`'s base64 output holds
    /// that invariant for the one part of the string that varies.
    public nonisolated static func contentSecurityPolicy(nonce: String) -> String {
        "default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; "
        + "img-src data: http: https:; font-src data:; base-uri 'none'; form-action 'none';"
    }

    /// Installs `contentSecurityPolicy(nonce:)` as a `<meta http-equiv>` before the
    /// document's own markup is parsed.
    ///
    /// At `.atDocumentStart` for a `loadHTMLString` load, `document.head` is
    /// still `null` — only `document.documentElement` exists. Reaching straight
    /// for `document.head` throws, and a throw here leaves the document with
    /// *no* policy at all rather than a loud failure, so every node this walks
    /// is created when it is missing instead of being dereferenced on faith.
    /// `PreviewWebViewLiveTests` asserts the meta really lands in a loaded
    /// document; this comment is not the guarantee, that test is.
    nonisolated static func cspUserScriptSource(nonce: String) -> String {
        """
        (function() {
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "\(contentSecurityPolicy(nonce: nonce))";
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

    /// The user content controller this view's policy is installed into.
    ///
    /// Held directly rather than reached through `configuration`, which
    /// `WKWebView` hands back as a copy: rotating the policy has to hit the
    /// object the web view is actually consulting, and this is the one that
    /// was handed to `super.init`.
    private let contentController: WKUserContentController

    /// The nonce the most recent `loadHTML(_:resourcesURL:nonce:)` installed.
    ///
    /// Exposed so a test can prove two loads got different values; nothing in
    /// the app reads it.
    public private(set) var installedNonce: String

    public init(frame: CGRect = .zero, imageTimeoutSeconds: TimeInterval = 3) {
        self.imageTimeoutSeconds = imageTimeoutSeconds

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        // A policy is installed before any load, not only in `loadHTML`, so a
        // document reaching this view through `WKWebView`'s own loading API
        // still gets one — one whose nonce no document can be carrying.
        let nonce = Self.makeNonce()
        self.installedNonce = nonce

        let contentController = WKUserContentController()
        self.contentController = contentController
        contentController.addUserScript(WKUserScript(
            source: Self.cspUserScriptSource(nonce: nonce),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        config.userContentController = contentController

        super.init(frame: frame, configuration: config)

        self.navigationDelegate = self
        self.setValue(false, forKey: "drawsBackground")
    }

    /// Replaces the installed policy with one naming `nonce` and nothing else.
    ///
    /// `removeAllUserScripts()` first: user scripts accumulate, and a second
    /// `<meta>` carrying the *previous* load's nonce would keep that nonce live
    /// for this document — CSP composes policies as an intersection, but two
    /// nonce policies would each admit their own document's scripts, so the
    /// stale one has to go rather than be joined.
    private func installCSPUserScript(nonce: String) {
        contentController.removeAllUserScripts()
        contentController.addUserScript(WKUserScript(
            source: Self.cspUserScriptSource(nonce: nonce),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        installedNonce = nonce
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

    /// Loads `html`, first arming the policy with the same `nonce` the document
    /// stamped on its own `<script>` elements.
    ///
    /// The nonce must be a fresh `makeNonce()` value per document. It cannot be
    /// generated here and handed back, because the document is composed —
    /// nonce and all — before the web view ever sees it; and it cannot live in
    /// the template alone, because WebKit ignores a parser-inserted meta CSP
    /// when a DOM-inserted one is already present, which is exactly what
    /// `cspUserScriptSource(nonce:)` creates. The user script's policy is the
    /// only policy the document actually gets.
    public func loadHTML(_ html: String, resourcesURL: URL?, nonce: String) {
        installCSPUserScript(nonce: nonce)
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
