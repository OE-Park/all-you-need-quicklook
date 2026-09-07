// Tests/PreviewWebViewNavigationTests.swift
import XCTest
import WebKit
@testable import Shared

/// The navigation policy used to gate on `navigationType` alone and allow
/// every `.other`. `.other` is the type of this view's own `loadHTMLString`
/// load — but it is equally the type of a `window.location = …`, a
/// `<meta http-equiv="refresh">` and a script-driven form submission, so the
/// spec's "external link navigation blocked" held only for the kinds a *user*
/// starts. These tests drive the real delegate method with the navigation
/// actions each of those produces.
@MainActor
final class PreviewWebViewNavigationTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

    private let resources = URL(fileURLWithPath: "/tmp/AllYouNeedQuickLook/Resources", isDirectory: true)

    // MARK: - The view's own load is allowed

    func testAllowsItsOwnLoadWithNoBaseURL() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: nil, nonce: nonce)
        await assertAllows(web, .other, URL(string: "about:blank"))
    }

    func testAllowsItsOwnLoadWithAFileBaseURL() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertAllows(web, .other, resources)
    }

    /// `resourcesURL` is a directory URL; WebKit does not promise to hand the
    /// string back byte-for-byte. A blank preview is the failure mode here.
    func testAllowsItsOwnLoadWhenTheBaseURLComesBackWithoutItsTrailingSlash() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertAllows(web, .other, URL(string: "file:///tmp/AllYouNeedQuickLook/Resources"))
    }

    // MARK: - Script-initiated navigation is blocked

    func testBlocksScriptInitiatedNavigationToHTTPS() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertAllows(web, .other, resources)  // the document loads,
        await assertCancels(web, .other, URL(string: "https://evil.example.com/"))  // and then cannot leave.
    }

    func testBlocksScriptInitiatedNavigationToHTTP() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: nil, nonce: nonce)
        await assertCancels(web, .other, URL(string: "http://evil.example.com/"))
    }

    /// A second `.other` navigation to the very base URL the load used is a
    /// document that noticed the exemption, not the load — the exemption is
    /// consumed by the load it was recorded for.
    func testBlocksASecondNavigationToTheBaseURL() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertAllows(web, .other, resources)
        await assertCancels(web, .other, resources)
    }

    func testBlocksNavigationToAnUnrelatedFileURL() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertCancels(web, .other, URL(fileURLWithPath: "/etc/passwd"))
    }

    // MARK: - User-initiated navigation stays blocked

    func testBlocksLinkActivation() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: nil, nonce: nonce)
        await assertCancels(web, .linkActivated, URL(string: "https://example.com/"))
    }

    func testBlocksFormSubmission() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: nil, nonce: nonce)
        await assertCancels(web, .formSubmitted, URL(string: "https://example.com/"))
    }

    /// Even a link back to the base URL: `.linkActivated` never gets the
    /// pending-load exemption.
    func testBlocksLinkActivationToTheBaseURL() async {
        let web = PreviewWebView()
        web.loadHTML("<html><body>x</body></html>", resourcesURL: resources, nonce: nonce)
        await assertCancels(web, .linkActivated, resources)
    }

    func testBlocksSecondBlankNavigationAndUnrequestedBlankLoad() async {
        let web = PreviewWebView()
        await assertCancels(web, .other, URL(string: "about:blank"))
        web.loadHTML("<html><body>x</body></html>", resourcesURL: nil, nonce: nonce)
        await assertAllows(web, .other, URL(string: "about:blank"))
        await assertCancels(web, .other, URL(string: "about:blank"))
    }

    // MARK: - Helpers

    private func decide(
        _ web: PreviewWebView,
        _ type: WKNavigationType,
        _ url: URL?
    ) async -> WKNavigationActionPolicy {
        await web.webView(web, decidePolicyFor: StubNavigationAction(type: type, url: url))
    }

    private func assertAllows(
        _ web: PreviewWebView,
        _ type: WKNavigationType,
        _ url: URL?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let policy = await decide(web, type, url)
        XCTAssertEqual(policy, .allow, "expected \(url?.absoluteString ?? "nil") to load", file: file, line: line)
    }

    private func assertCancels(
        _ web: PreviewWebView,
        _ type: WKNavigationType,
        _ url: URL?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let policy = await decide(web, type, url)
        XCTAssertEqual(policy, .cancel, "\(url?.absoluteString ?? "nil") was allowed to navigate", file: file, line: line)
    }
}

/// `WKNavigationAction` has no public initialiser that sets these; both
/// properties are readonly Objective-C properties, so a subclass overriding
/// them is the only way to hand the real delegate method a chosen navigation.
private final class StubNavigationAction: WKNavigationAction {
    private let type: WKNavigationType
    private let url: URL?

    init(type: WKNavigationType, url: URL?) {
        self.type = type
        self.url = url
        super.init()
    }

    override var navigationType: WKNavigationType { type }
    override var request: URLRequest { url.map { URLRequest(url: $0) } ?? URLRequest(url: URL(string: "about:blank")!) }
}
