import Foundation
import WebKit

final class BundledResourceSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    nonisolated static let scheme = "quicklook-resource"

    private let lock = NSLock()
    private var rootURL: URL?

    func setRootURL(_ url: URL?) {
        lock.withLock {
            rootURL = url?.standardizedFileURL
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.host == "bundle",
              let resourceName = resourceName(from: requestURL),
              let rootURL = lock.withLock({ self.rootURL }) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = rootURL.appendingPathComponent(resourceName).standardizedFileURL
        guard fileURL.deletingLastPathComponent() == rootURL,
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType(for: fileURL.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: textEncoding(for: fileURL.pathExtension)
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func resourceName(from url: URL) -> String? {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        return name
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "js": "text/javascript"
        case "css": "text/css"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        default: "application/octet-stream"
        }
    }

    private func textEncoding(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "js", "css": "utf-8"
        default: nil
        }
    }
}
