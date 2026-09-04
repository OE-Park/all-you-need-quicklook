import WebKit
import XCTest
@testable import Shared

final class PreviewNavigationPolicyTests: XCTestCase {

    func testBlocksProgrammaticExternalNavigation() {
        let policy = PreviewNavigationPolicy.decide(
            requestURL: URL(string: "https://example.com/redirect"),
            currentURL: URL(string: "about:blank"),
            navigationType: .other
        )

        XCTAssertEqual(policy, .cancel)
    }

    func testAllowsInitialLocalDocumentNavigation() {
        let policy = PreviewNavigationPolicy.decide(
            requestURL: URL(string: "about:blank"),
            currentURL: nil,
            navigationType: .other
        )

        XCTAssertEqual(policy, .allow)
    }

    func testAllowsInitialBundledDocumentNavigation() {
        let bundledRoot = URL(string: "quicklook-resource://bundle/")
        let initialStates: [URL?] = [nil, URL(string: "about:blank"), bundledRoot]

        for currentURL in initialStates {
            let policy = PreviewNavigationPolicy.decide(
                requestURL: bundledRoot,
                currentURL: currentURL,
                navigationType: .other
            )

            XCTAssertEqual(policy, .allow)
        }
    }

    func testAllowsSameDocumentAnchorOnly() {
        let currentURL = URL(string: "quicklook-resource://bundle/#top")

        XCTAssertEqual(
            PreviewNavigationPolicy.decide(
                requestURL: URL(string: "quicklook-resource://bundle/#details"),
                currentURL: currentURL,
                navigationType: .linkActivated
            ),
            .allow
        )
        XCTAssertEqual(
            PreviewNavigationPolicy.decide(
                requestURL: URL(string: "https://example.com/#details"),
                currentURL: currentURL,
                navigationType: .linkActivated
            ),
            .cancel
        )
    }

    func testAllowsBundledDocumentAnchorWhenWebViewReportsAboutBlank() {
        XCTAssertEqual(
            PreviewNavigationPolicy.decide(
                requestURL: URL(string: "quicklook-resource://bundle/#details"),
                currentURL: URL(string: "about:blank"),
                navigationType: .linkActivated
            ),
            .allow
        )
    }
}
