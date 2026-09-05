// Tests/PreviewWebViewCSPTests.swift
import XCTest
@testable import Shared

/// Locks the Content Security Policy to the shape the preview documents need.
///
/// The policy and `HTMLTemplate` are one contract: the template inlines every
/// bundled library because the policy names no script or style source other
/// than this document's nonce and `'unsafe-inline'` style, and the policy can
/// stay that narrow because the template inlines them and stamps the nonce.
/// Either half drifting silently breaks previews or silently unblocks
/// third-party code, so both halves are asserted here.
final class PreviewWebViewCSPTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

    private var policy: String { PreviewWebView.contentSecurityPolicy(nonce: nonce) }

    private func directive(_ name: String) throws -> [String] {
        let policy = self.policy
        let clause = try XCTUnwrap(
            policy.split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0 == name || $0.hasPrefix(name + " ") },
            "CSP has no \(name) directive: \(policy)"
        )
        return clause.split(separator: " ").dropFirst().map(String.init)
    }

    // MARK: - The nonce itself

    /// A nonce that repeats across documents is no better than
    /// `'unsafe-inline'` for the notebook `text/html` path, whose markup is
    /// parser-inserted and could simply carry the known value.
    func testEveryNonceIsDifferent() {
        let nonces = (0..<64).map { _ in PreviewWebView.makeNonce() }
        XCTAssertEqual(Set(nonces).count, nonces.count, "makeNonce() repeated a value")
    }

    /// 16 random bytes, base64. The alphabet matters as much as the entropy:
    /// it is what lets the value be interpolated into the policy string, the
    /// injection script's JS string literal and a `<script nonce="…">`
    /// attribute with no escaping anywhere.
    func testNonceIsBase64OfSixteenBytes() {
        for _ in 0..<64 {
            let nonce = PreviewWebView.makeNonce()
            XCTAssertEqual(nonce.count, 24, "expected base64 of 16 bytes: \(nonce)")
            let allowed = CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
            XCTAssertTrue(allowed.isSuperset(of: CharacterSet(charactersIn: nonce)),
                          "nonce is not base64: \(nonce)")
        }
    }

    // MARK: - Admits the bundled subresources

    func testPolicyAdmitsInlinedBundledScriptsByNonce() throws {
        XCTAssertTrue(try directive("script-src").contains("'nonce-\(nonce)'"),
                      "bundled marked.js/highlight.js/KaTeX are inlined and would not run")
    }

    func testPolicyAdmitsInlinedBundledStyles() throws {
        let styleSrc = try directive("style-src")
        XCTAssertTrue(styleSrc.contains("'unsafe-inline'"),
                      "bundled KaTeX/highlight.js CSS is inlined and would not apply")
    }

    /// Every subresource form the template emits must be one the policy admits.
    func testPolicyAdmitsEverySubresourceFormTheTemplateEmits() throws {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown", nonce: nonce)
        let scriptSrc = try directive("script-src")
        let styleSrc = try directive("style-src")

        // Inline script — admitted only by this document's nonce, which the
        // template must therefore stamp on every `<script>` it writes.
        XCTAssertFalse(html.contains("<script>"),
                       "an unstamped <script> would be refused by script-src")
        XCTAssertTrue(html.contains("<script nonce=\"\(nonce)\">"))
        XCTAssertTrue(scriptSrc.contains("'nonce-\(nonce)'"))

        // Inline style — admitted by 'unsafe-inline'.
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(styleSrc.contains("'unsafe-inline'"))

        // Linked forms would need a host or scheme source the policy lacks.
        // `'self'` does not help: the document's origin is opaque.
        XCTAssertFalse(html.contains("<script src="),
                       "template links external JS but script-src names no source for it")
        XCTAssertFalse(html.contains("<link rel=\"stylesheet\""),
                       "template links external CSS but style-src names no source for it")
    }

    // MARK: - Still blocks third-party resources

    /// `script-src` is pinned by *shape* rather than by an exact string,
    /// because its one source now varies per load. The shape is the whole
    /// point: exactly one source, and that source a nonce. `'unsafe-inline'`
    /// alongside a nonce would not merely be redundant — CSP2 parsers ignore
    /// the nonce when it is present, so re-adding it silently restores every
    /// inline script. `'strict-dynamic'` would let the nonced libraries inject
    /// further scripts of their own choosing.
    func testPolicyAllowsExactlyOneScriptSourceAndItIsANonce() throws {
        let scriptSrc = try directive("script-src")
        XCTAssertEqual(scriptSrc.count, 1, "script-src names more than the nonce: \(scriptSrc)")
        let source = try XCTUnwrap(scriptSrc.first)
        XCTAssertTrue(source.hasPrefix("'nonce-"), "script-src source is not a nonce: \(source)")
        XCTAssertTrue(source.hasSuffix("'"))
        XCTAssertEqual(source, "'nonce-\(nonce)'")
        XCTAssertFalse(scriptSrc.contains("'unsafe-inline'"))
        XCTAssertFalse(scriptSrc.contains("'unsafe-eval'"))
        XCTAssertFalse(scriptSrc.contains("'strict-dynamic'"))
        XCTAssertFalse(scriptSrc.contains("'self'"))
    }

    /// Pinned as an exact allow-list rather than a deny-list of shapes: a
    /// deny-list has to anticipate every form a third-party source can take
    /// (`cdn.example.com`, `//evil.com`, `*.example.com`, `data:`,
    /// `'strict-dynamic'`, …) and misses the bare-host form anyone is most
    /// likely to actually write. Anything added here now fails the test.
    func testPolicyAllowsExactlyTheInlineStyleSource() throws {
        XCTAssertEqual(try directive("style-src"), ["'unsafe-inline'"],
                       "style-src names a source nothing in this project emits")
    }

    func testPolicyBlocksFramesAndEverythingElseByDefault() throws {
        XCTAssertEqual(try directive("default-src"), ["'none'"],
                       "default-src must stay 'none' so iframes and the rest are blocked")
        XCTAssertFalse(policy.contains("frame-src"), "no frame-src may override default-src 'none'")
        XCTAssertFalse(policy.contains("child-src"), "no child-src may override default-src 'none'")
    }

    /// Neither directive falls back to `default-src`, so `'none'` there does
    /// not cover them: without these an injected `<base href>` would retarget
    /// every relative URL in the document, and an injected `<form>` could post
    /// the preview's contents anywhere.
    func testPolicyPinsBaseURIAndFormAction() throws {
        XCTAssertEqual(try directive("base-uri"), ["'none'"])
        XCTAssertEqual(try directive("form-action"), ["'none'"])
    }

    // MARK: - Deliberate allowances

    func testPolicyKeepsExternalImagesAndDataURIFonts() throws {
        XCTAssertEqual(try directive("img-src"), ["data:", "http:", "https:"])
        XCTAssertEqual(try directive("font-src"), ["data:"])
    }

    /// Nothing but `script-src` changed when the nonce arrived.
    func testOnlyScriptSrcVariesWithTheNonce() {
        let a = PreviewWebView.contentSecurityPolicy(nonce: "AAAA")
        let b = PreviewWebView.contentSecurityPolicy(nonce: "BBBB")
        XCTAssertEqual(a.replacingOccurrences(of: "'nonce-AAAA'", with: "X"),
                       b.replacingOccurrences(of: "'nonce-BBBB'", with: "X"),
                       "the nonce is not the only part of the policy that varies")
    }

    // MARK: - Injection

    // Whether the policy is actually installed in a loaded document, and
    // actually enforced once it is, is asserted against a live WKWebView in
    // PreviewWebViewLiveTests. Asserting on the shape of the injection source
    // here would pass for a script that builds a head and then forgets to put
    // the meta in it, and fail for a correct refactor that used double quotes.

    /// The policy is interpolated into a JS double-quoted string literal.
    func testPolicyIsSafeToEmbedInAJavaScriptStringLiteral() {
        for _ in 0..<64 {
            let policy = PreviewWebView.contentSecurityPolicy(nonce: PreviewWebView.makeNonce())
            XCTAssertFalse(policy.contains("\""))
            XCTAssertFalse(policy.contains("\\"))
            XCTAssertFalse(policy.contains("\n"))
        }
    }
}
