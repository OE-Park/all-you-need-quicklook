import AppKit
import WebKit
import Shared

@MainActor
func inspect(_ name: String, content: String, config: AppConfig) async {
    let web = PreviewWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let nonce = PreviewWebView.makeNonce()
    web.loadHTML(PlainTextRenderer().render(content: content, config: config, fileExtension: "log", nonce: nonce), resourcesURL: Bundle(for: ConfigLoader.self).resourceURL, nonce: nonce)
    for _ in 0..<200 {
        if (try? await web.evaluateJavaScript("document.documentElement.dataset.quicklookReady === 'true'")) as? Bool == true { break }
        try? await Task.sleep(for: .milliseconds(20))
    }
    let js = """
    JSON.stringify({ready:document.documentElement.dataset.quicklookReady,
      text:document.querySelector('pre')?.textContent,
      preFont:getComputedStyle(document.querySelector('pre')).fontFamily,
      codeFont:document.querySelector('code') ? getComputedStyle(document.querySelector('code')).fontFamily : null,
      html:document.querySelector('pre')?.innerHTML})
    """
    print(name, (try? await web.evaluateJavaScript(js)) ?? "failed")
}

let app = NSApplication.shared
Task { @MainActor in
    var config = AppConfig()
    config.fileTypes = ["log": FileTypeConfig(fontFamily: "Courier", showLineNumbers: false, syntaxHighlight: true, syntaxLanguage: "plaintext")]
    await inspect("highlight-font", content: "font check", config: config)
    config.fileTypes = ["log": FileTypeConfig(showLineNumbers: false, logLevelPatterns: ["error": "&"])]
    await inspect("pattern-on-entities", content: "a < b & c", config: config)
    config.fileTypes = ["log": FileTypeConfig(showLineNumbers: false, logLevelPatterns: ["error": "ERROR", "warn": "(?i)error"])]
    await inspect("pattern-on-generated-markup", content: "ERROR", config: config)
    exit(0)
}
app.run()
