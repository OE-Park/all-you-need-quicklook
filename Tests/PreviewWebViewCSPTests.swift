// Tests/PreviewWebViewCSPTests.swift
import XCTest
@testable import Shared

/// Locks the Content Security Policy to the shape the preview documents need.
///
/// The policy and `HTMLTemplate` are one contract: the template inlines every
/// bundled library because the policy names no script or style source other
/// than `'unsafe-inline'`, and the policy can stay that narrow because the
/// template inlines them. Either half drifting silently breaks previews or
/// silently unblocks third-party code, so both halves are asserted here.
final class PreviewWebViewCSPTests: XCTestCase {

    private func directive(_ name: String) throws -> [String] {
        let policy = PreviewWebView.contentSecurityPolicy
        let clause = try XCTUnwrap(
            policy.split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0 == name || $0.hasPrefix(name + " ") },
            "CSP has no \(name) directive: \(policy)"
        )
        return clause.split(separator: " ").dropFirst().map(String.init)
    }

    // MARK: - Admits the bundled subresources

    func testPolicyAdmitsInlinedBundledScripts() throws {
        XCTAssertTrue(try directive("script-src").contains("'unsafe-inline'"),
                      "bundled marked.js/highlight.js/KaTeX are inlined and would not run")
    }

    func testPolicyAdmitsInlinedBundledStyles() throws {
        let styleSrc = try directive("style-src")
        XCTAssertTrue(styleSrc.contains("'unsafe-inline'"),
                      "bundled KaTeX/highlight.js CSS is inlined and would not apply")
    }

    /// Every subresource form the template emits must be one the policy admits.
    func testPolicyAdmitsEverySubresourceFormTheTemplateEmits() throws {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        let scriptSrc = try directive("script-src")
        let styleSrc = try directive("style-src")

        // Inline forms — admitted by 'unsafe-inline'.
        XCTAssertTrue(html.contains("<script>"))
        XCTAssertTrue(scriptSrc.contains("'unsafe-inline'"))
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

    func testPolicyBlocksThirdPartyScriptAndStyle() throws {
        for source in try directive("script-src") + directive("style-src") {
            XCTAssertFalse(source.hasPrefix("http"), "third-party origin allowed: \(source)")
            XCTAssertNotEqual(source, "*")
            XCTAssertNotEqual(source, "'unsafe-eval'")
        }
    }

    func testPolicyBlocksFramesAndEverythingElseByDefault() throws {
        XCTAssertEqual(try directive("default-src"), ["'none'"],
                       "default-src must stay 'none' so iframes and the rest are blocked")
        let policy = PreviewWebView.contentSecurityPolicy
        XCTAssertFalse(policy.contains("frame-src"), "no frame-src may override default-src 'none'")
        XCTAssertFalse(policy.contains("child-src"), "no child-src may override default-src 'none'")
    }

    // MARK: - Deliberate allowances

    func testPolicyKeepsExternalImagesAndDataURIFonts() throws {
        XCTAssertEqual(try directive("img-src"), ["data:", "http:", "https:"])
        XCTAssertEqual(try directive("font-src"), ["data:"])
    }

    // MARK: - Injection

    /// `document.head` is nil at `.atDocumentStart` for a `loadHTMLString`
    /// load. Dereferencing it throws and leaves the document with no policy at
    /// all, so the script must create the head itself.
    func testInjectionScriptDoesNotAssumeDocumentHeadExists() {
        let source = PreviewWebView.cspUserScriptSource
        XCTAssertTrue(source.contains("document.createElement('head')"),
                      "injection must cope with a document that has no head yet")
        XCTAssertTrue(source.contains(PreviewWebView.contentSecurityPolicy),
                      "injection must carry the policy verbatim")
    }

    /// The policy is interpolated into a JS double-quoted string literal.
    func testPolicyIsSafeToEmbedInAJavaScriptStringLiteral() {
        let policy = PreviewWebView.contentSecurityPolicy
        XCTAssertFalse(policy.contains("\""))
        XCTAssertFalse(policy.contains("\\"))
        XCTAssertFalse(policy.contains("\n"))
    }
}
