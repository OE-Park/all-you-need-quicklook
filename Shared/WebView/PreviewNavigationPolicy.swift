import Foundation
import WebKit

enum PreviewNavigationPolicy {
    static func decide(
        requestURL: URL?,
        currentURL: URL?,
        navigationType: WKNavigationType
    ) -> WKNavigationActionPolicy {
        guard let requestURL else { return .cancel }

        if navigationType == .other,
           requestURL.absoluteString == "about:blank" {
            return .allow
        }

        if navigationType == .other,
           isBundledDocumentRoot(requestURL),
           (currentURL == nil
               || currentURL?.absoluteString == "about:blank"
               || currentURL == requestURL) {
            return .allow
        }

        if navigationType == .linkActivated,
           requestURL.fragment != nil,
           sameDocument(requestURL, currentURL) || isBundledDocumentAnchor(requestURL) {
            return .allow
        }

        return .cancel
    }

    private static func sameDocument(_ lhs: URL, _ rhs: URL?) -> Bool {
        guard let rhs,
              var left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
              var right = URLComponents(url: rhs, resolvingAgainstBaseURL: false) else {
            return false
        }
        left.fragment = nil
        right.fragment = nil
        return left == right
    }

    private static func isBundledDocumentAnchor(_ url: URL) -> Bool {
        isBundledDocumentRoot(url) && url.fragment != nil
    }

    private static func isBundledDocumentRoot(_ url: URL) -> Bool {
        url.scheme == BundledResourceSchemeHandler.scheme
            && url.host == "bundle"
            && url.path == "/"
    }
}
