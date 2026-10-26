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
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin1
        } else {
            content = try String(contentsOf: url, encoding: .utf8)
        }

        let fileExtension = url.pathExtension.lowercased()
        let config = configLoader.load()

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
        let html = renderer.render(
            content: content, config: config, fileExtension: fileExtension, nonce: nonce
        )

        let resourcesURL = Bundle(for: PreviewWebView.self).resourceURL
            ?? Bundle(for: Self.self).resourceURL
            ?? Bundle.main.resourceURL

        await MainActor.run {
            // A reused QuickLook controller must not retain the previous
            // document's network consent, timeout or in-flight requests.
            replaceWebView(config: config)
            webView.loadHTML(html, resourcesURL: resourcesURL, nonce: nonce)
        }
    }
}
