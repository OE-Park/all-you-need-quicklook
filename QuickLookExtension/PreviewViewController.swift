// QuickLookExtension/PreviewViewController.swift
import Cocoa
import Quartz
import WebKit
import Shared

class PreviewViewController: NSViewController, QLPreviewingController {

    var configLoader = ConfigLoader()

    private var webView: PreviewWebView!

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    private func replaceWebView(config: AppConfig) {
        let frame = view.bounds
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = PreviewWebView(
            frame: frame,
            imageTimeoutSeconds: TimeInterval(config.global.imageTimeoutSeconds),
            allowExternalImages: config.global.allowExternalImages
        )
        webView.autoresizingMask = [.width, .height]
        view.addSubview(webView)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let content = try SourceTextDecoder.read(from: url)

        let fileExtension = url.pathExtension.lowercased()
        let configResult = configLoader.loadResult()
        let config = configResult.config

        let renderer: Renderer = switch fileExtension {
        case "md", "markdown":
            MarkdownRenderer()
        case "ipynb":
            NotebookRenderer()
        default:
            PlainTextRenderer()
        }

        // One nonce per document, generated here and handed to both halves:
        // the renderer stamps it on the `<script>` elements it emits, and the
        // web view arms `script-src 'nonce-…'` with the same value.
        let nonce = PreviewWebView.makeNonce()
        let document = renderer.render(
            content: content, config: config, fileExtension: fileExtension, nonce: nonce
        )

        let html = PreviewBuildIdentity.annotate(document, identifier: Bundle.main.bundleIdentifier)

        let resourcesURL = Bundle(for: PreviewWebView.self).resourceURL
            ?? Bundle(for: Self.self).resourceURL
            ?? Bundle.main.resourceURL

        await MainActor.run {
            // A reused QuickLook controller must not retain the previous
            // document's network consent, timeout or in-flight requests.
            replaceWebView(config: config)
            webView.loadHTML(
                html, resourcesURL: resourcesURL, nonce: nonce,
                notice: configResult.isUnreadable ? PreviewWebView.unreadableSettingsNotice : nil,
                documentDirectory: url.deletingLastPathComponent()
            )
        }
    }
}
