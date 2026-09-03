// Shared/WebView/PreviewWebView.swift
import WebKit

public final class PreviewWebView: WKWebView {

    private let resourceHandler: BundledResourceSchemeHandler
    private let imageHandler: ExternalImageSchemeHandler

    public init(frame: CGRect = .zero, imageTimeoutSeconds: TimeInterval = 3) {
        let resourceHandler = BundledResourceSchemeHandler()
        self.resourceHandler = resourceHandler
        let imageHandler = ExternalImageSchemeHandler(timeout: imageTimeoutSeconds)
        self.imageHandler = imageHandler

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
        config.setURLSchemeHandler(resourceHandler, forURLScheme: BundledResourceSchemeHandler.scheme)
        config.setURLSchemeHandler(imageHandler, forURLScheme: ExternalImageSchemeHandler.scheme)

        super.init(frame: frame, configuration: config)

        self.navigationDelegate = self
        self.setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func loadHTML(_ html: String, resourcesURL: URL?) {
        if let baseURL = resourcesURL {
            resourceHandler.setRootURL(baseURL)
            loadHTMLString(
                html,
                baseURL: URL(string: "\(BundledResourceSchemeHandler.scheme)://bundle/")
            )
        } else {
            resourceHandler.setRootURL(nil)
            loadHTMLString(html, baseURL: nil)
        }
    }
}

extension PreviewWebView: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        PreviewNavigationPolicy.decide(
            requestURL: navigationAction.request.url,
            currentURL: webView.url,
            navigationType: navigationAction.navigationType
        )
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        .allow
    }
}
