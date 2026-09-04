// AllYouNeedQuickLook/Views/PreviewWebViewRepresentable.swift
import SwiftUI
import Shared

struct PreviewWebViewRepresentable: NSViewRepresentable {
    let html: String
    let resourcesURL: URL?

    /// Remembers what the web view is already showing.
    ///
    /// SwiftUI calls `updateNSView` on every state invalidation, not only when
    /// `html` changes. Reloading unconditionally tore down and re-parsed the
    /// whole document each time — and since the libraries were inlined, that
    /// document is ~475 KB of minified JS, with a visible flash.
    final class Coordinator {
        var loadedHTML: String?
        var loadedResourcesURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewWebView {
        let webView = PreviewWebView()
        loadIfNeeded(webView, context.coordinator)
        return webView
    }

    func updateNSView(_ webView: PreviewWebView, context: Context) {
        loadIfNeeded(webView, context.coordinator)
    }

    private func loadIfNeeded(_ webView: PreviewWebView, _ coordinator: Coordinator) {
        guard coordinator.loadedHTML != html || coordinator.loadedResourcesURL != resourcesURL else { return }
        coordinator.loadedHTML = html
        coordinator.loadedResourcesURL = resourcesURL
        webView.loadHTML(html, resourcesURL: resourcesURL)
    }
}
