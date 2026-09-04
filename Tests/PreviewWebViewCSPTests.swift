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

    /// Pinned as exact allow-lists rather than a deny-list of shapes: a
    /// deny-list has to anticipate every form a third-party source can take
    /// (`cdn.example.com`, `//evil.com`, `*.example.com`, `data:`,
    /// `'strict-dynamic'`, …) and misses the bare-host form anyone is most
    /// likely to actually write. Anything added here now fails the test.
    func testPolicyAllowsExactlyTheInlineScriptAndStyleSources() throws {
        XCTAssertEqual(try directive("script-src"), ["'unsafe-inline'"])
        XCTAssertEqual(try directive("style-src"), ["'unsafe-inline'"],
                       "style-src names a source nothing in this project emits")
    }

    func testPolicyBlocksFramesAndEverythingElseByDefault() throws {
        XCTAssertEqual(try directive("default-src"), ["'none'"],
                       "default-src must stay 'none' so iframes and the rest are blocked")
        let policy = PreviewWebView.contentSecurityPolicy
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

    // MARK: - Injection

    // Whether the policy is actually installed in a loaded document, and
    // actually enforced once it is, is asserted against a live WKWebView in
    // PreviewWebViewLiveTests. Asserting on the shape of the injection source
    // here would pass for a script that builds a head and then forgets to put
    // the meta in it, and fail for a correct refactor that used double quotes.

    /// The policy is interpolated into a JS double-quoted string literal.
    func testPolicyIsSafeToEmbedInAJavaScriptStringLiteral() {
        let policy = PreviewWebView.contentSecurityPolicy
        XCTAssertFalse(policy.contains("\""))
        XCTAssertFalse(policy.contains("\\"))
        XCTAssertFalse(policy.contains("\n"))
    }
}
