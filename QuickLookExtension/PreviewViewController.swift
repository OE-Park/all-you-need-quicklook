// QuickLookExtension/PreviewViewController.swift
import Cocoa
import Quartz
import WebKit
import Shared

class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: PreviewWebView!

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let config = ConfigLoader().load()
        webView = PreviewWebView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400),
            imageTimeoutSeconds: TimeInterval(config.global.imageTimeoutSeconds)
        )
        webView.autoresizingMask = [.width, .height]
        self.view = webView
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
        let config = ConfigLoader().load()

        let renderer: Renderer = switch fileExtension {
        case "md", "markdown":
            MarkdownRenderer()
        case "ipynb":
            NotebookRenderer()
        default:
            PlainTextRenderer()
        }

        let html = renderer.render(content: content, config: config, fileExtension: fileExtension)

        let resourcesURL = Bundle(for: PreviewWebView.self).resourceURL
            ?? Bundle(for: Self.self).resourceURL
            ?? Bundle.main.resourceURL

        await MainActor.run {
            _ = self.view
            webView.loadHTML(html, resourcesURL: resourcesURL)
        }
    }
}
