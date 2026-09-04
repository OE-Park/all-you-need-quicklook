// AllYouNeedQuickLook/Views/PreviewWebViewRepresentable.swift
import SwiftUI
import Shared

struct PreviewWebViewRepresentable: NSViewRepresentable {
    let html: String
    let resourcesURL: URL?

    func makeNSView(context: Context) -> PreviewWebView {
        let webView = PreviewWebView()
        webView.loadHTML(html, resourcesURL: resourcesURL)
        return webView
    }

    func updateNSView(_ webView: PreviewWebView, context: Context) {
        webView.loadHTML(html, resourcesURL: resourcesURL)
    }
}
