import AppKit
import WebKit
import XCTest
@testable import Shared

/// Session-only probe of the owner's current system appearance; not a portable CI test.
@MainActor
final class DarkModeValidationTests: XCTestCase {
    func testMarkdownDarkAppearance() async throws { try await verify("md") }
    func testNotebookDarkAppearance() async throws { try await verify("ipynb") }
    func testLogDarkAppearance() async throws { try await verify("log") }
    func testTextDarkAppearance() async throws { try await verify("txt") }

    private func verify(_ ext: String) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("AllYouNeedQuickLook/SampleFiles/sample.\(ext)")
        let content = try String(contentsOf: url, encoding: .utf8)
        let renderer: Renderer = switch ext {
        case "md": MarkdownRenderer()
        case "ipynb": NotebookRenderer()
        default: PlainTextRenderer()
        }
        let nonce = PreviewWebView.makeNonce()
        let web = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        defer { window.contentView = nil }
        web.loadHTML(renderer.render(content: content, config: ConfigLoader.bundledDefault(), fileExtension: ext, nonce: nonce), resourcesURL: Bundle(for: ConfigLoader.self).resourceURL, nonce: nonce)
        var ready = false
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("document.documentElement.dataset.quicklookReady === 'true'")) as? Bool == true {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(ready, "preview finished")
        let evaluated = try await web.evaluateJavaScript("""
        (() => {
            const css = getComputedStyle(document.body);
            const code = document.querySelector('pre code');
            const error = document.querySelector('.log-error');
            return {
                dark: matchMedia('(prefers-color-scheme: dark)').matches,
                background: css.backgroundColor, text: css.color,
                contentLength: document.body.innerText.length,
                highlight: code ? getComputedStyle(code).backgroundColor : '',
                errorColor: error ? getComputedStyle(error).color : '',
                darkTheme: [...document.querySelectorAll('style[media]')].some(s => s.media.includes('dark') && matchMedia(s.media).matches)
            };
        })()
        """)
        let result = try XCTUnwrap(evaluated as? [String: Any])
        print("DARK_PROBE \(ext): \(result)")
        XCTAssertEqual(result["dark"] as? Bool, true)
        XCTAssertEqual(result["background"] as? String, "rgb(29, 29, 31)")
        XCTAssertEqual(result["text"] as? String, "rgb(245, 245, 247)")
        XCTAssertEqual(result["darkTheme"] as? Bool, true)
        XCTAssertGreaterThan(result["contentLength"] as? Int ?? 0, 30)
        if ext == "md" || ext == "ipynb" {
            XCTAssertEqual(result["highlight"] as? String, "rgb(13, 17, 23)")
        }
        if ext == "log" {
            XCTAssertEqual(result["errorColor"] as? String, "rgb(255, 107, 107)")
        }
    }
}
