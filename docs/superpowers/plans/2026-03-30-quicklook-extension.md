# AllYouNeedQuickLook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS QuickLook Preview Extension that renders Markdown, plain text/log, and Jupyter Notebook files through a unified WKWebView HTML pipeline.

**Architecture:** Host app (SwiftUI, 3 tabs) bundles a QuickLook Preview Extension. All file types are converted to HTML by Swift renderers, then displayed in WKWebView. JSON config in App Group container controls per-extension formatting. JS libraries (marked.js, highlight.js, KaTeX) are bundled for browser-side rendering.

**Tech Stack:** Swift, SwiftUI, WebKit (WKWebView), XCTest, marked.js, highlight.js, KaTeX

**Spec:** `docs/superpowers/specs/2026-03-30-quicklook-extension-design.md`

**Security Note — actual threat model:** A previewed file **can run script**. This is a
deliberate, currently-accepted position, not an accident, and it is written down here so
nobody re-derives it from the code.

What is true:

- Every renderer HTML-escapes the text it injects, and every Swift value interpolated into
  an inline `<script>` goes through `Shared/Renderers/ScriptEscaping.swift`, which
  neutralises `</script` as well as the JavaScript literal it lands in. A previewed file
  therefore cannot end a script element and be parsed as document markup.
- The CSP (`Shared/WebView/PreviewWebView.swift`) is `default-src 'none'` with
  `script-src 'unsafe-inline'`, `style-src 'unsafe-inline'`, `img-src data: http: https:`,
  `font-src data:`, `base-uri 'none'` and `form-action 'none'`. External JS, external CSS,
  frames, `eval`, XHR/fetch/WebSocket (no `connect-src`) and form posts are all blocked.
- `WKNavigationDelegate` cancels every navigation except this view's own document load —
  script-initiated (`window.location`, meta refresh) included.

What is **not** true, and is the reason a previewed file can run script:

- **Markdown source is not sanitized.** `MarkdownRenderer` does
  `container.innerHTML = marked.parse(raw)`. marked has shipped no sanitizer since v5 and
  the bundled build is v15, so raw HTML in a `.md` file — `<img src=x onerror=…>`, an
  inline event handler on anything — reaches the DOM as markup.
- **Notebook `text/html` output is injected unescaped by design**
  (`NotebookRenderer.renderMimeData`), matching Jupyter's own trust model.
- `script-src 'unsafe-inline'` admits both of those, and inline `<script>` elements from
  either path (an `innerHTML`-inserted `<script>` does not execute, but an inline event
  handler does).

So the blast radius of a malicious preview is: **arbitrary script in an opaque-origin
document with no `connect-src`, whose only outbound channel is `img-src http: https:`**
(exfiltration by image URL). The QuickLook extension additionally holds
`com.apple.security.network.client`, so that channel does reach the network. There is no
access to the file system, to other origins, or to the host app's data.

Closing this would take either sanitizing marked's output (e.g. DOMPurify) or moving
`script-src` to a nonce so only the template's own scripts run. Neither is implemented:
which one to take is a product decision the owner has not made yet. Do not "fix" this in
passing — raise it.

---

## File Map

### Shared/ (shared framework target — used by both host app and extension)

| File | Responsibility |
|------|---------------|
| `Shared/Models/ConfigSchema.swift` | Codable structs for JSON config (GlobalConfig, FileTypeConfig, AppConfig) |
| `Shared/Models/NotebookSchema.swift` | Codable structs for .ipynb JSON (Notebook, Cell, Output, CellType) |
| `Shared/Config/ConfigLoader.swift` | Read/write JSON config from App Group container, fallback to defaults |
| `Shared/Renderers/RenderProtocol.swift` | `Renderer` protocol — `func render(content: String, config: AppConfig, fileExtension: String) -> String` |
| `Shared/Renderers/MarkdownRenderer.swift` | Markdown content → HTML (wraps in template, marked.js renders in browser) |
| `Shared/Renderers/PlainTextRenderer.swift` | Plain text → HTML with config-based CSS, log level highlighting |
| `Shared/Renderers/NotebookRenderer.swift` | ipynb JSON → HTML (parses cells, generates HTML for each output type) |
| `Shared/Renderers/ANSIConverter.swift` | ANSI escape codes → `<span style="color:...">` HTML |
| `Shared/Renderers/HTMLTemplate.swift` | Base HTML template with CSS variables, JS imports, dark mode |

### QuickLookExtension/

| File | Responsibility |
|------|---------------|
| `QuickLookExtension/PreviewViewController.swift` | QLPreviewingController — routes file to renderer, loads into WKWebView |
| `QuickLookExtension/WebView/PreviewWebView.swift` | WKWebView subclass with security policies, 3s image timeout, navigation blocking |
| `QuickLookExtension/Info.plist` | QLSupportedContentTypes, UTExportedTypeDeclarations |
| `QuickLookExtension/QuickLookExtension.entitlements` | Sandbox + network.client + app-groups |

### AllYouNeedQuickLook/ (host app)

| File | Responsibility |
|------|---------------|
| `AllYouNeedQuickLook/App.swift` | App entry point with TabView |
| `AllYouNeedQuickLook/Views/WelcomeView.swift` | Extension activation guide + status |
| `AllYouNeedQuickLook/Views/SettingsView.swift` | JSON config GUI editor |
| `AllYouNeedQuickLook/Views/PreviewView.swift` | Sample file list + rendered preview |
| `AllYouNeedQuickLook/Views/PreviewWebViewRepresentable.swift` | NSViewRepresentable wrapper for WKWebView in SwiftUI |
| `AllYouNeedQuickLook/AllYouNeedQuickLook.entitlements` | Sandbox + app-groups |

### Resources (bundled in Shared/)

| File | Responsibility |
|------|---------------|
| `Shared/Resources/js/marked.min.js` | Markdown parser |
| `Shared/Resources/js/highlight.min.js` | Code syntax highlighting |
| `Shared/Resources/js/katex.min.js` | LaTeX math rendering |
| `Shared/Resources/css/katex.min.css` | KaTeX styles + fonts |
| `Shared/Resources/css/highlight-light.min.css` | highlight.js light theme |
| `Shared/Resources/css/highlight-dark.min.css` | highlight.js dark theme |
| `Shared/Resources/default-config.json` | Default configuration file |

### Sample Files (bundled in host app)

| File | Responsibility |
|------|---------------|
| `AllYouNeedQuickLook/SampleFiles/sample.md` | Markdown with headings, code, tables, math |
| `AllYouNeedQuickLook/SampleFiles/sample.txt` | Plain text |
| `AllYouNeedQuickLook/SampleFiles/sample.log` | Log with ERROR/WARN/INFO/DEBUG lines |
| `AllYouNeedQuickLook/SampleFiles/sample.ipynb` | Notebook with code, markdown, image outputs |

### Tests

| File | Responsibility |
|------|---------------|
| `Tests/ConfigSchemaTests.swift` | Config JSON encode/decode, null inheritance |
| `Tests/ConfigLoaderTests.swift` | Load/save/fallback behavior |
| `Tests/MarkdownRendererTests.swift` | Markdown → HTML output |
| `Tests/PlainTextRendererTests.swift` | Plain text + log level highlighting |
| `Tests/NotebookRendererTests.swift` | ipynb cell types → HTML |
| `Tests/ANSIConverterTests.swift` | ANSI codes → HTML spans |
| `Tests/HTMLTemplateTests.swift` | Template injection, dark mode CSS |

---

## Task 1: Xcode Project Setup

**Files:**
- Create: Xcode project `AllYouNeedQuickLook.xcodeproj` with 3 targets
- Create: `AllYouNeedQuickLook/App.swift`
- Create: `AllYouNeedQuickLook/AllYouNeedQuickLook.entitlements`
- Create: `QuickLookExtension/PreviewViewController.swift` (stub)
- Create: `QuickLookExtension/Info.plist`
- Create: `QuickLookExtension/QuickLookExtension.entitlements`

- [ ] **Step 1: Create Xcode project via `xcodegen`**

Install xcodegen if not present, then create `project.yml`:

```yaml
name: AllYouNeedQuickLook
options:
  deploymentTarget:
    macOS: "15.0"
  bundleIdPrefix: com.yohanpark
  xcodeVersion: "16.0"
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"

targets:
  AllYouNeedQuickLook:
    type: application
    platform: macOS
    sources:
      - AllYouNeedQuickLook
    dependencies:
      - target: Shared
      - target: QuickLookExtension
        embed: true
        codeSign: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yohanpark.AllYouNeedQuickLook
        INFOPLIST_KEY_CFBundleDisplayName: "All You Need QuickLook"
    entitlements:
      path: AllYouNeedQuickLook/AllYouNeedQuickLook.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups:
          - group.com.yohanpark.AllYouNeedQuickLook

  QuickLookExtension:
    type: appex
    platform: macOS
    sources:
      - QuickLookExtension
    dependencies:
      - target: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yohanpark.AllYouNeedQuickLook.QuickLookExtension
    info:
      path: QuickLookExtension/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.quicklook.preview
          NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).PreviewViewController"
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: org.jupyter.notebook
            UTTypeDescription: Jupyter Notebook
            UTTypeConformsTo:
              - public.json
            UTTypeTagSpecification:
              public.filename-extension:
                - ipynb
        QLSupportedContentTypes:
          - public.plain-text
          - net.daringfireball.markdown
          - org.jupyter.notebook
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
    entitlements:
      path: QuickLookExtension/QuickLookExtension.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
        com.apple.security.application-groups:
          - group.com.yohanpark.AllYouNeedQuickLook

  Shared:
    type: framework
    platform: macOS
    sources:
      - Shared
    resources:
      - Shared/Resources/**

  Tests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: Shared
```

Run: `xcodegen generate`

- [ ] **Step 2: Create stub App.swift**

```swift
// AllYouNeedQuickLook/App.swift
import SwiftUI

@main
struct AllYouNeedQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            Text("AllYouNeedQuickLook")
        }
    }
}
```

- [ ] **Step 3: Create stub PreviewViewController**

```swift
// QuickLookExtension/PreviewViewController.swift
import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        self.view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // TODO: implement in Task 12
    }
}
```

- [ ] **Step 4: Create directory structure and placeholder files**

```bash
mkdir -p AllYouNeedQuickLook/Views
mkdir -p AllYouNeedQuickLook/SampleFiles
mkdir -p QuickLookExtension/WebView
mkdir -p Shared/Models
mkdir -p Shared/Config
mkdir -p Shared/Renderers
mkdir -p Shared/WebView
mkdir -p Shared/Resources/js
mkdir -p Shared/Resources/css
mkdir -p Tests
```

- [ ] **Step 5: Generate project and verify build**

```bash
xcodegen generate
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold Xcode project with host app, extension, and shared framework"
```

---

## Task 2: ConfigSchema — Shared Codable Models

**Files:**
- Create: `Shared/Models/ConfigSchema.swift`
- Create: `Tests/ConfigSchemaTests.swift`

- [ ] **Step 1: Write failing tests for ConfigSchema**

```swift
// Tests/ConfigSchemaTests.swift
import XCTest
@testable import Shared

final class ConfigSchemaTests: XCTestCase {

    func testDecodeFullConfig() throws {
        let json = """
        {
            "version": 1,
            "global": {
                "fontFamily": "SF Mono",
                "fontSize": 13,
                "lineHeight": 1.5,
                "showLineNumbers": true,
                "imageTimeoutSeconds": 3
            },
            "fileTypes": {
                "log": {
                    "syntaxHighlight": true,
                    "logLevelPatterns": {
                        "error": "\\\\b(ERROR)\\\\b",
                        "warn": "\\\\b(WARN)\\\\b"
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.fontFamily, "SF Mono")
        XCTAssertEqual(config.global.fontSize, 13)
        XCTAssertEqual(config.fileTypes?["log"]?.syntaxHighlight, true)
        XCTAssertEqual(config.fileTypes?["log"]?.logLevelPatterns?["error"], "\\b(ERROR)\\b")
    }

    func testNullFieldsInheritFromGlobal() throws {
        let global = GlobalConfig(
            fontFamily: "SF Mono",
            fontSize: 13,
            lineHeight: 1.5,
            showLineNumbers: true,
            imageTimeoutSeconds: 3
        )
        let fileType = FileTypeConfig(
            fontFamily: nil,
            fontSize: 16,
            lineHeight: nil,
            showLineNumbers: nil,
            syntaxHighlight: nil,
            syntaxLanguage: nil,
            logLevelPatterns: nil
        )
        let resolved = fileType.resolved(with: global)
        XCTAssertEqual(resolved.fontFamily, "SF Mono")    // inherited
        XCTAssertEqual(resolved.fontSize, 16)              // overridden
        XCTAssertEqual(resolved.lineHeight, 1.5)           // inherited
        XCTAssertEqual(resolved.showLineNumbers, true)     // inherited
    }

    func testEncodeRoundTrip() throws {
        let config = AppConfig(
            version: 1,
            global: GlobalConfig(
                fontFamily: "Menlo",
                fontSize: 14,
                lineHeight: 1.6,
                showLineNumbers: false,
                imageTimeoutSeconds: 5
            ),
            fileTypes: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.global.fontFamily, "Menlo")
        XCTAssertEqual(decoded.global.imageTimeoutSeconds, 5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `AppConfig`, `GlobalConfig`, `FileTypeConfig` not found

- [ ] **Step 3: Implement ConfigSchema**

```swift
// Shared/Models/ConfigSchema.swift
import Foundation

public struct GlobalConfig: Codable, Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Int
    public var lineHeight: Double
    public var showLineNumbers: Bool
    public var imageTimeoutSeconds: Int

    public init(
        fontFamily: String = "SF Mono",
        fontSize: Int = 13,
        lineHeight: Double = 1.5,
        showLineNumbers: Bool = true,
        imageTimeoutSeconds: Int = 3
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.showLineNumbers = showLineNumbers
        self.imageTimeoutSeconds = imageTimeoutSeconds
    }
}

public struct FileTypeConfig: Codable, Equatable, Sendable {
    public var fontFamily: String?
    public var fontSize: Int?
    public var lineHeight: Double?
    public var showLineNumbers: Bool?
    public var syntaxHighlight: Bool?
    public var syntaxLanguage: String?
    public var logLevelPatterns: [String: String]?

    public init(
        fontFamily: String? = nil,
        fontSize: Int? = nil,
        lineHeight: Double? = nil,
        showLineNumbers: Bool? = nil,
        syntaxHighlight: Bool? = nil,
        syntaxLanguage: String? = nil,
        logLevelPatterns: [String: String]? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.showLineNumbers = showLineNumbers
        self.syntaxHighlight = syntaxHighlight
        self.syntaxLanguage = syntaxLanguage
        self.logLevelPatterns = logLevelPatterns
    }
}

public struct ResolvedFileTypeConfig: Sendable {
    public let fontFamily: String
    public let fontSize: Int
    public let lineHeight: Double
    public let showLineNumbers: Bool
    public let syntaxHighlight: Bool
    public let syntaxLanguage: String?
    public let logLevelPatterns: [String: String]?
}

extension FileTypeConfig {
    public func resolved(with global: GlobalConfig) -> ResolvedFileTypeConfig {
        ResolvedFileTypeConfig(
            fontFamily: fontFamily ?? global.fontFamily,
            fontSize: fontSize ?? global.fontSize,
            lineHeight: lineHeight ?? global.lineHeight,
            showLineNumbers: showLineNumbers ?? global.showLineNumbers,
            syntaxHighlight: syntaxHighlight ?? false,
            syntaxLanguage: syntaxLanguage,
            logLevelPatterns: logLevelPatterns
        )
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var global: GlobalConfig
    public var fileTypes: [String: FileTypeConfig]?

    public init(
        version: Int = 1,
        global: GlobalConfig = GlobalConfig(),
        fileTypes: [String: FileTypeConfig]? = nil
    ) {
        self.version = version
        self.global = global
        self.fileTypes = fileTypes
    }

    public func resolvedConfig(for fileExtension: String) -> ResolvedFileTypeConfig {
        let fileType = fileTypes?[fileExtension] ?? FileTypeConfig()
        return fileType.resolved(with: global)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/ConfigSchema.swift Tests/ConfigSchemaTests.swift
git commit -m "feat: add ConfigSchema with global/per-extension config and null inheritance"
```

---

## Task 3: ConfigLoader — Read/Write from App Group

**Files:**
- Create: `Shared/Config/ConfigLoader.swift`
- Create: `Shared/Resources/default-config.json`
- Create: `Tests/ConfigLoaderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/ConfigLoaderTests.swift
import XCTest
@testable import Shared

final class ConfigLoaderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadDefaultConfigWhenNoFileExists() {
        let loader = ConfigLoader(containerURL: tempDir)
        let config = loader.load()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.fontFamily, "SF Mono")
        XCTAssertEqual(config.global.fontSize, 13)
    }

    func testSaveAndLoad() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        var config = AppConfig()
        config.global.fontSize = 18
        try loader.save(config)

        let loaded = loader.load()
        XCTAssertEqual(loaded.global.fontSize, 18)
    }

    func testLoadFallsBackOnCorruptFile() throws {
        let corruptPath = tempDir.appendingPathComponent("config.json")
        try "not json".write(to: corruptPath, atomically: true, encoding: .utf8)

        let loader = ConfigLoader(containerURL: tempDir)
        let config = loader.load()
        XCTAssertEqual(config.version, 1) // falls back to default
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `ConfigLoader` not found

- [ ] **Step 3: Create default-config.json**

```json
{
  "version": 1,
  "global": {
    "fontFamily": "SF Mono",
    "fontSize": 13,
    "lineHeight": 1.5,
    "showLineNumbers": true,
    "imageTimeoutSeconds": 3
  },
  "fileTypes": {
    "txt": {
      "showLineNumbers": false,
      "syntaxHighlight": false
    },
    "log": {
      "syntaxHighlight": true,
      "logLevelPatterns": {
        "error": "\\b(ERROR|FATAL|CRITICAL)\\b",
        "warn": "\\b(WARN|WARNING)\\b",
        "info": "\\b(INFO)\\b",
        "debug": "\\b(DEBUG|TRACE)\\b"
      }
    }
  }
}
```

- [ ] **Step 4: Implement ConfigLoader**

```swift
// Shared/Config/ConfigLoader.swift
import Foundation

public final class ConfigLoader: Sendable {
    private let containerURL: URL
    private let configFileName = "config.json"

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public convenience init() {
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yohanpark.AllYouNeedQuickLook"
        ) ?? FileManager.default.temporaryDirectory
        self.init(containerURL: groupURL)
    }

    private var configFileURL: URL {
        containerURL.appendingPathComponent(configFileName)
    }

    public func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return loadBundledDefault()
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return loadBundledDefault()
        }
    }

    public func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
    }

    private func loadBundledDefault() -> AppConfig {
        guard let url = Bundle(for: Self.self).url(forResource: "default-config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return config
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Shared/Config/ConfigLoader.swift Shared/Resources/default-config.json Tests/ConfigLoaderTests.swift
git commit -m "feat: add ConfigLoader with App Group persistence and default fallback"
```

---

## Task 4: HTMLTemplate — Base Template with Dark Mode

**Files:**
- Create: `Shared/Renderers/HTMLTemplate.swift`
- Create: `Tests/HTMLTemplateTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/HTMLTemplateTests.swift
import XCTest
@testable import Shared

final class HTMLTemplateTests: XCTestCase {

    func testTemplateContainsContent() {
        let html = HTMLTemplate.wrap(body: "<p>Hello</p>", rendererType: "markdown")
        XCTAssertTrue(html.contains("<p>Hello</p>"))
    }

    func testTemplateHasDarkModeCSS() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "plaintext")
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    func testTemplateIncludesRendererTypeClass() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "notebook")
        XCTAssertTrue(html.contains("class=\"notebook\""))
    }

    func testTemplateWithCustomCSS() {
        let css = "--custom-font: Menlo; --custom-size: 16px;"
        let html = HTMLTemplate.wrap(body: "<pre>test</pre>", rendererType: "plaintext", customCSS: css)
        XCTAssertTrue(html.contains(css))
    }

    func testTemplateIncludesJSLibraries() {
        let html = HTMLTemplate.wrap(body: "", rendererType: "markdown")
        XCTAssertTrue(html.contains("marked.min.js"))
        XCTAssertTrue(html.contains("highlight.min.js"))
        XCTAssertTrue(html.contains("katex.min.js"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `HTMLTemplate` not found

- [ ] **Step 3: Implement HTMLTemplate**

```swift
// Shared/Renderers/HTMLTemplate.swift
import Foundation

public enum HTMLTemplate {

    public static func wrap(
        body: String,
        rendererType: String,
        customCSS: String = ""
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --bg: #ffffff;
            --text: #1d1d1f;
            --code-bg: #f5f5f7;
            --code-text: #1d1d1f;
            --border: #d2d2d7;
            --cell-bg: #f9f9f9;
            --output-bg: #ffffff;
            --error-bg: #fff0f0;
            --error-text: #d32f2f;
            --warn-text: #f57c00;
            --info-text: #1976d2;
            --debug-text: #7b7b7b;
            --line-number: #999999;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #1d1d1f;
                --text: #f5f5f7;
                --code-bg: #2c2c2e;
                --code-text: #f5f5f7;
                --border: #48484a;
                --cell-bg: #2c2c2e;
                --output-bg: #1d1d1f;
                --error-bg: #3c1a1a;
                --error-text: #ff6b6b;
                --warn-text: #ffb74d;
                --info-text: #64b5f6;
                --debug-text: #9e9e9e;
                --line-number: #666666;
            }
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: var(--bg);
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            line-height: 1.6;
            padding: 24px;
            -webkit-font-smoothing: antialiased;
        }
        pre, code {
            font-family: "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
        }
        pre {
            background: var(--code-bg);
            color: var(--code-text);
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 13px;
            line-height: 1.5;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
        }
        th, td {
            border: 1px solid var(--border);
            padding: 8px 12px;
            text-align: left;
        }
        th { background: var(--code-bg); }
        .log-error { color: var(--error-text); font-weight: 600; }
        .log-warn { color: var(--warn-text); font-weight: 600; }
        .log-info { color: var(--info-text); }
        .log-debug { color: var(--debug-text); }
        .line-number {
            display: inline-block;
            width: 4em;
            text-align: right;
            padding-right: 1em;
            color: var(--line-number);
            user-select: none;
            -webkit-user-select: none;
        }
        .notebook-cell {
            margin-bottom: 16px;
            border: 1px solid var(--border);
            border-radius: 8px;
            overflow: hidden;
        }
        .cell-source {
            background: var(--cell-bg);
            padding: 12px 16px;
        }
        .cell-output {
            background: var(--output-bg);
            padding: 12px 16px;
            border-top: 1px solid var(--border);
        }
        .cell-output pre {
            background: transparent;
            padding: 0;
            border-radius: 0;
        }
        .cell-error {
            background: var(--error-bg);
        }
        .cell-execution-count {
            font-size: 11px;
            color: var(--line-number);
            padding: 4px 16px 0;
        }
        .markdown-cell { padding: 16px; }
        .markdown-cell h1, .markdown-cell h2, .markdown-cell h3,
        .markdown-cell h4, .markdown-cell h5, .markdown-cell h6 {
            margin-top: 1em;
            margin-bottom: 0.5em;
        }
        .markdown-cell p { margin: 0.5em 0; }
        .markdown-cell ul, .markdown-cell ol { padding-left: 2em; }
        .placeholder-image {
            background: var(--code-bg);
            border: 1px dashed var(--border);
            border-radius: 4px;
            padding: 20px;
            text-align: center;
            color: var(--line-number);
            font-size: 12px;
        }
        \(customCSS)
        </style>
        <link rel="stylesheet" href="katex.min.css">
        <link rel="stylesheet" href="highlight-light.min.css" media="(prefers-color-scheme: light)">
        <link rel="stylesheet" href="highlight-dark.min.css" media="(prefers-color-scheme: dark)">
        <script src="marked.min.js"></script>
        <script src="highlight.min.js"></script>
        <script src="katex.min.js"></script>
        </head>
        <body class="\(rendererType)">
        \(body)
        </body>
        </html>
        """
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Shared/Renderers/HTMLTemplate.swift Tests/HTMLTemplateTests.swift
git commit -m "feat: add HTMLTemplate with dark mode CSS variables and JS library imports"
```

---

## Task 5: ANSIConverter — ANSI Escape Codes to HTML

**Files:**
- Create: `Shared/Renderers/ANSIConverter.swift`
- Create: `Tests/ANSIConverterTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/ANSIConverterTests.swift
import XCTest
@testable import Shared

final class ANSIConverterTests: XCTestCase {

    func testPlainTextPassesThrough() {
        let result = ANSIConverter.toHTML("Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testRedText() {
        let input = "\u{1B}[31mError occurred\u{1B}[0m"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("color:"))
        XCTAssertTrue(result.contains("Error occurred"))
        XCTAssertFalse(result.contains("\u{1B}"))
    }

    func testBoldText() {
        let input = "\u{1B}[1mBold text\u{1B}[0m"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("font-weight:bold"))
        XCTAssertTrue(result.contains("Bold text"))
    }

    func testNestedStyles() {
        let input = "\u{1B}[1;31mBold red\u{1B}[0m normal"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("Bold red"))
        XCTAssertTrue(result.contains("normal"))
    }

    func testHTMLEntitiesEscaped() {
        let input = "<script>alert('xss')</script>"
        let result = ANSIConverter.toHTML(input)
        XCTAssertFalse(result.contains("<script>"))
        XCTAssertTrue(result.contains("&lt;script&gt;"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `ANSIConverter` not found

- [ ] **Step 3: Implement ANSIConverter**

```swift
// Shared/Renderers/ANSIConverter.swift
import Foundation

public enum ANSIConverter {

    private static let ansiColors: [Int: String] = [
        30: "#1d1d1f", 31: "#d32f2f", 32: "#388e3c", 33: "#f57c00",
        34: "#1976d2", 35: "#7b1fa2", 36: "#0097a7", 37: "#f5f5f7",
        90: "#7b7b7b", 91: "#ff6b6b", 92: "#66bb6a", 93: "#ffb74d",
        94: "#64b5f6", 95: "#ce93d8", 96: "#4dd0e1", 97: "#ffffff",
    ]

    private static let ansiPattern = try! NSRegularExpression(
        pattern: "\u{1B}\\[([0-9;]*)m",
        options: []
    )

    public static func toHTML(_ input: String) -> String {
        let escaped = escapeHTML(input)
        let nsString = escaped as NSString
        let matches = ansiPattern.matches(
            in: escaped,
            range: NSRange(location: 0, length: nsString.length)
        )

        guard !matches.isEmpty else { return escaped }

        var result = ""
        var lastIndex = escaped.startIndex
        var spanOpen = false

        for match in matches {
            guard let fullRange = Range(match.range, in: escaped),
                  let codeRange = Range(match.range(at: 1), in: escaped) else { continue }

            result += escaped[lastIndex..<fullRange.lowerBound]
            let codes = escaped[codeRange].split(separator: ";").compactMap { Int($0) }

            if spanOpen {
                result += "</span>"
                spanOpen = false
            }

            let styles = buildStyles(from: codes)
            if !styles.isEmpty {
                result += "<span style=\"\(styles)\">"
                spanOpen = true
            }

            lastIndex = fullRange.upperBound
        }

        result += escaped[lastIndex...]
        if spanOpen { result += "</span>" }

        return result
    }

    private static func buildStyles(from codes: [Int]) -> String {
        var parts: [String] = []
        for code in codes {
            if code == 0 { return "" }
            if code == 1 { parts.append("font-weight:bold") }
            if code == 3 { parts.append("font-style:italic") }
            if code == 4 { parts.append("text-decoration:underline") }
            if let color = ansiColors[code] {
                parts.append("color:\(color)")
            }
        }
        return parts.joined(separator: ";")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Shared/Renderers/ANSIConverter.swift Tests/ANSIConverterTests.swift
git commit -m "feat: add ANSI escape code to HTML converter with XSS escaping"
```

---

## Task 6: Renderer Protocol + MarkdownRenderer

**Files:**
- Create: `Shared/Renderers/RenderProtocol.swift`
- Create: `Shared/Renderers/MarkdownRenderer.swift`
- Create: `Tests/MarkdownRendererTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/MarkdownRendererTests.swift
import XCTest
@testable import Shared

final class MarkdownRendererTests: XCTestCase {

    let renderer = MarkdownRenderer()
    let config = AppConfig()

    func testRendersMarkdownInTemplate() {
        let md = "# Hello World\n\nSome **bold** text."
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("class=\"markdown\""))
        XCTAssertTrue(html.contains("# Hello World"))
        XCTAssertTrue(html.contains("marked.min.js"))
    }

    func testContainsMarkedParseScript() {
        let md = "test"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("marked.parse"))
    }

    func testContainsKaTeXRenderScript() {
        let md = "Inline $E=mc^2$ math"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        XCTAssertTrue(html.contains("renderMathInElement") || html.contains("katex"))
    }

    func testEscapesContentForJavaScript() {
        let md = "line with `backtick` and \\ backslash and 'quote'"
        let html = renderer.render(content: md, config: config, fileExtension: "md")
        // Content should be embedded safely in a JS template literal
        XCTAssertTrue(html.contains("\\\\"))  // backslash escaped
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `Renderer`, `MarkdownRenderer` not found

- [ ] **Step 3: Implement RenderProtocol**

```swift
// Shared/Renderers/RenderProtocol.swift
import Foundation

public protocol Renderer {
    func render(content: String, config: AppConfig, fileExtension: String) -> String
}
```

- [ ] **Step 4: Implement MarkdownRenderer**

The MarkdownRenderer embeds the raw markdown into a JS template literal. The Swift side escapes backslashes, backticks, and dollar signs to safely embed in JS. The browser-side marked.js then parses the markdown and sets the output via DOM manipulation. Content is escaped for JS embedding — marked.js produces sanitized HTML from markdown syntax.

```swift
// Shared/Renderers/MarkdownRenderer.swift
import Foundation

public final class MarkdownRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        let escapedContent = escapeForJS(content)
        // The markdown content is escaped for safe JS template literal embedding.
        // marked.js parses the markdown and produces HTML. highlight.js and KaTeX
        // process code blocks and math expressions respectively. All JS is bundled
        // locally — no external scripts are loaded (enforced by CSP).
        let body = """
        <div id="markdown-content"></div>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            const raw = `\(escapedContent)`;
            marked.setOptions({
                highlight: function(code, lang) {
                    if (lang && hljs.getLanguage(lang)) {
                        return hljs.highlight(code, { language: lang }).value;
                    }
                    return hljs.highlightAuto(code).value;
                },
                gfm: true,
                breaks: false
            });
            var rendered = marked.parse(raw);
            document.getElementById('markdown-content').innerHTML = rendered;

            renderMathInElement(document.getElementById('markdown-content'));
        });

        function renderMathInElement(element) {
            var text = element.innerHTML;
            text = text.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(match, math) {
                try {
                    return katex.renderToString(math.trim(), { displayMode: true, throwOnError: false });
                } catch(e) { return match; }
            });
            text = text.replace(/\\$([^\\$\\n]+?)\\$/g, function(match, math) {
                try {
                    return katex.renderToString(math.trim(), { displayMode: false, throwOnError: false });
                } catch(e) { return match; }
            });
            element.innerHTML = text;
        }
        </script>
        """
        return HTMLTemplate.wrap(body: body, rendererType: "markdown")
    }

    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Shared/Renderers/RenderProtocol.swift Shared/Renderers/MarkdownRenderer.swift Tests/MarkdownRendererTests.swift
git commit -m "feat: add Renderer protocol and MarkdownRenderer with marked.js + KaTeX"
```

---

## Task 7: PlainTextRenderer

**Files:**
- Create: `Shared/Renderers/PlainTextRenderer.swift`
- Create: `Tests/PlainTextRendererTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/PlainTextRendererTests.swift
import XCTest
@testable import Shared

final class PlainTextRendererTests: XCTestCase {

    let renderer = PlainTextRenderer()

    func testBasicTextRendering() {
        let config = AppConfig()
        let html = renderer.render(content: "Hello world", config: config, fileExtension: "txt")
        XCTAssertTrue(html.contains("class=\"plaintext\""))
        XCTAssertTrue(html.contains("Hello world"))
        XCTAssertTrue(html.contains("<pre"))
    }

    func testAppliesCustomFont() {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(fontFamily: "Menlo", fontSize: 16)]
        let html = renderer.render(content: "test", config: config, fileExtension: "txt")
        XCTAssertTrue(html.contains("Menlo"))
        XCTAssertTrue(html.contains("16px"))
    }

    func testLogLevelHighlighting() {
        var config = AppConfig()
        config.fileTypes = [
            "log": FileTypeConfig(
                syntaxHighlight: true,
                logLevelPatterns: [
                    "error": "\\b(ERROR)\\b",
                    "warn": "\\b(WARN)\\b",
                    "info": "\\b(INFO)\\b"
                ]
            )
        ]
        let logContent = "[2024-01-01] ERROR Something failed\n[2024-01-01] INFO All good\n[2024-01-01] WARN Be careful"
        let html = renderer.render(content: logContent, config: config, fileExtension: "log")
        XCTAssertTrue(html.contains("log-error"))
        XCTAssertTrue(html.contains("log-info"))
        XCTAssertTrue(html.contains("log-warn"))
    }

    func testLineNumbers() {
        var config = AppConfig()
        config.global.showLineNumbers = true
        let html = renderer.render(content: "line1\nline2\nline3", config: config, fileExtension: "txt")
        XCTAssertTrue(html.contains("line-number"))
    }

    func testNoLineNumbersWhenDisabled() {
        var config = AppConfig()
        config.fileTypes = ["txt": FileTypeConfig(showLineNumbers: false)]
        let html = renderer.render(content: "line1\nline2", config: config, fileExtension: "txt")
        XCTAssertFalse(html.contains("line-number"))
    }

    func testSyntaxHighlightWithLanguage() {
        var config = AppConfig()
        config.fileTypes = ["plist": FileTypeConfig(syntaxHighlight: true, syntaxLanguage: "xml")]
        let html = renderer.render(content: "<plist></plist>", config: config, fileExtension: "plist")
        XCTAssertTrue(html.contains("hljs.highlight"))
        XCTAssertTrue(html.contains("xml"))
    }

    func testHTMLEscaping() {
        let config = AppConfig()
        let html = renderer.render(content: "<script>alert('xss')</script>", config: config, fileExtension: "txt")
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `PlainTextRenderer` not found

- [ ] **Step 3: Implement PlainTextRenderer**

```swift
// Shared/Renderers/PlainTextRenderer.swift
import Foundation

public final class PlainTextRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        let resolved = config.resolvedConfig(for: fileExtension)
        let lines = content.components(separatedBy: "\n")

        let customCSS = """
        pre.plaintext-content {
            font-family: "\(resolved.fontFamily)", monospace;
            font-size: \(resolved.fontSize)px;
            line-height: \(resolved.lineHeight);
        }
        """

        if resolved.syntaxHighlight, let language = resolved.syntaxLanguage {
            return renderWithSyntaxHighlight(
                content: content,
                language: language,
                resolved: resolved,
                customCSS: customCSS
            )
        }

        let processedLines = lines.enumerated().map { index, line in
            let escapedLine = applyLogPatterns(
                escapeHTML(line),
                patterns: resolved.logLevelPatterns
            )
            if resolved.showLineNumbers {
                let num = String(index + 1)
                return "<span class=\"line-number\">\(num)</span>\(escapedLine)"
            }
            return escapedLine
        }

        let body = "<pre class=\"plaintext-content\">\(processedLines.joined(separator: "\n"))</pre>"
        return HTMLTemplate.wrap(body: body, rendererType: "plaintext", customCSS: customCSS)
    }

    // Syntax highlight uses highlight.js in the browser. The content is
    // escaped for JS template literal embedding, then hljs.highlight()
    // processes it. The result is set via DOM — hljs produces safe HTML
    // with <span class="hljs-..."> wrappers only.
    private func renderWithSyntaxHighlight(
        content: String,
        language: String,
        resolved: ResolvedFileTypeConfig,
        customCSS: String
    ) -> String {
        let escaped = escapeForJS(content)
        let body = """
        <pre class="plaintext-content"><code id="code-content" class="language-\(language)"></code></pre>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var raw = `\(escaped)`;
            var result = hljs.highlight(raw, { language: '\(language)' });
            document.getElementById('code-content').innerHTML = result.value;
        });
        </script>
        """
        return HTMLTemplate.wrap(body: body, rendererType: "plaintext", customCSS: customCSS)
    }

    private func applyLogPatterns(_ line: String, patterns: [String: String]?) -> String {
        guard let patterns = patterns else { return line }
        var result = line
        let levelToClass = ["error": "log-error", "warn": "log-warn", "info": "log-info", "debug": "log-debug"]
        for (level, pattern) in patterns {
            guard let cssClass = levelToClass[level],
                  let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let matched = result[range]
                result = result.replacingCharacters(
                    in: range,
                    with: "<span class=\"\(cssClass)\">\(matched)</span>"
                )
            }
        }
        return result
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Shared/Renderers/PlainTextRenderer.swift Tests/PlainTextRendererTests.swift
git commit -m "feat: add PlainTextRenderer with log level highlighting and syntax highlight"
```

---

## Task 8: NotebookSchema — ipynb Codable Models

**Files:**
- Create: `Shared/Models/NotebookSchema.swift`
- Create: `Tests/NotebookSchemaTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/NotebookSchemaTests.swift
import XCTest
@testable import Shared

final class NotebookSchemaTests: XCTestCase {

    func testDecodeMinimalNotebook() throws {
        let json = """
        {
            "nbformat": 4,
            "nbformat_minor": 5,
            "metadata": {},
            "cells": [
                {
                    "cell_type": "markdown",
                    "metadata": {},
                    "source": ["# Title\\n", "Some text"]
                },
                {
                    "cell_type": "code",
                    "metadata": {},
                    "source": ["print('hello')"],
                    "execution_count": 1,
                    "outputs": [
                        {
                            "output_type": "stream",
                            "name": "stdout",
                            "text": ["hello\\n"]
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        XCTAssertEqual(notebook.cells.count, 2)
        XCTAssertEqual(notebook.cells[0].cellType, .markdown)
        XCTAssertEqual(notebook.cells[0].joinedSource, "# Title\nSome text")
        XCTAssertEqual(notebook.cells[1].cellType, .code)
        XCTAssertEqual(notebook.cells[1].executionCount, 1)
        XCTAssertEqual(notebook.cells[1].outputs?.count, 1)
    }

    func testDecodeOutputTypes() throws {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{
                "cell_type": "code", "metadata": {}, "source": [""],
                "execution_count": null,
                "outputs": [
                    { "output_type": "stream", "name": "stdout", "text": ["out\\n"] },
                    { "output_type": "display_data", "metadata": {},
                      "data": { "image/png": "iVBOR...", "text/plain": ["<Figure>"] } },
                    { "output_type": "execute_result", "execution_count": 2, "metadata": {},
                      "data": { "text/html": ["<b>bold</b>"], "text/plain": ["bold"] } },
                    { "output_type": "error", "ename": "ValueError", "evalue": "bad",
                      "traceback": ["\\u001b[31mValueError\\u001b[0m: bad"] }
                ]
            }]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        let outputs = notebook.cells[0].outputs!
        XCTAssertEqual(outputs.count, 4)

        switch outputs[0] {
        case .stream(let s): XCTAssertEqual(s.text.joined(), "out\n")
        default: XCTFail("Expected stream")
        }

        switch outputs[1] {
        case .displayData(let d): XCTAssertNotNil(d.data["image/png"])
        default: XCTFail("Expected display_data")
        }

        switch outputs[2] {
        case .executeResult(let r): XCTAssertEqual(r.executionCount, 2)
        default: XCTFail("Expected execute_result")
        }

        switch outputs[3] {
        case .error(let e):
            XCTAssertEqual(e.ename, "ValueError")
            XCTAssertEqual(e.traceback.count, 1)
        default: XCTFail("Expected error")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `Notebook` not found

- [ ] **Step 3: Implement NotebookSchema**

```swift
// Shared/Models/NotebookSchema.swift
import Foundation

public struct Notebook: Codable, Sendable {
    public let nbformat: Int
    public let nbformatMinor: Int
    public let cells: [Cell]

    enum CodingKeys: String, CodingKey {
        case nbformat
        case nbformatMinor = "nbformat_minor"
        case cells
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nbformat = try container.decode(Int.self, forKey: .nbformat)
        nbformatMinor = try container.decode(Int.self, forKey: .nbformatMinor)
        cells = try container.decode([Cell].self, forKey: .cells)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nbformat, forKey: .nbformat)
        try container.encode(nbformatMinor, forKey: .nbformatMinor)
        try container.encode(cells, forKey: .cells)
        try container.encode([String: String](), forKey: .metadata)
    }
}

public enum CellType: String, Codable, Sendable {
    case markdown
    case code
    case raw
}

public struct Cell: Codable, Sendable {
    public let cellType: CellType
    public let source: [String]
    public let outputs: [CellOutput]?
    public let executionCount: Int?

    public var joinedSource: String { source.joined() }

    enum CodingKeys: String, CodingKey {
        case cellType = "cell_type"
        case source, outputs, metadata
        case executionCount = "execution_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cellType = try container.decode(CellType.self, forKey: .cellType)
        source = try container.decode([String].self, forKey: .source)
        outputs = try container.decodeIfPresent([CellOutput].self, forKey: .outputs)
        executionCount = try container.decodeIfPresent(Int?.self, forKey: .executionCount) ?? nil
    }
}

public enum CellOutput: Codable, Sendable {
    case stream(StreamOutput)
    case displayData(DisplayDataOutput)
    case executeResult(ExecuteResultOutput)
    case error(ErrorOutput)

    enum CodingKeys: String, CodingKey {
        case outputType = "output_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .outputType)
        switch type {
        case "stream":
            self = .stream(try StreamOutput(from: decoder))
        case "display_data":
            self = .displayData(try DisplayDataOutput(from: decoder))
        case "execute_result":
            self = .executeResult(try ExecuteResultOutput(from: decoder))
        case "error":
            self = .error(try ErrorOutput(from: decoder))
        default:
            self = .stream(StreamOutput(name: "stdout", text: ["[unsupported output type: \(type)]"]))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .stream(let o): try o.encode(to: encoder)
        case .displayData(let o): try o.encode(to: encoder)
        case .executeResult(let o): try o.encode(to: encoder)
        case .error(let o): try o.encode(to: encoder)
        }
    }
}

public struct StreamOutput: Codable, Sendable {
    public let name: String
    public let text: [String]
}

public struct DisplayDataOutput: Codable, Sendable {
    public let data: [String: MimeData]

    enum CodingKeys: String, CodingKey {
        case data, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([String: MimeData].self, forKey: .data)
    }
}

public struct ExecuteResultOutput: Codable, Sendable {
    public let executionCount: Int?
    public let data: [String: MimeData]

    enum CodingKeys: String, CodingKey {
        case executionCount = "execution_count"
        case data, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executionCount = try container.decodeIfPresent(Int.self, forKey: .executionCount)
        data = try container.decode([String: MimeData].self, forKey: .data)
    }
}

public struct ErrorOutput: Codable, Sendable {
    public let ename: String
    public let evalue: String
    public let traceback: [String]
}

public enum MimeData: Codable, Sendable {
    case string(String)
    case array([String])

    public var text: String {
        switch self {
        case .string(let s): return s
        case .array(let a): return a.joined()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/NotebookSchema.swift Tests/NotebookSchemaTests.swift
git commit -m "feat: add Notebook Codable models for ipynb JSON parsing"
```

---

## Task 9: NotebookRenderer

**Files:**
- Create: `Shared/Renderers/NotebookRenderer.swift`
- Create: `Tests/NotebookRendererTests.swift`

- [x] **Step 1: Write failing tests**

```swift
// Tests/NotebookRendererTests.swift
import XCTest
@testable import Shared

final class NotebookRendererTests: XCTestCase {

    let renderer = NotebookRenderer()
    let config = AppConfig()

    private func makeNotebookJSON(cells: String) -> String {
        """
        {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[\(cells)]}
        """
    }

    func testMarkdownCellRendered() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"markdown","metadata":{},"source":["# Title"]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("markdown-cell"))
        XCTAssertTrue(html.contains("# Title"))
    }

    func testCodeCellWithOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["print('hi')"],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["hi\\n"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("cell-source"))
        XCTAssertTrue(html.contains("print("))
        XCTAssertTrue(html.contains("cell-output"))
        XCTAssertTrue(html.contains("hi"))
    }

    func testBase64ImageOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"iVBORw0KGgo=","text/plain":["<Figure>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("data:image/png;base64,iVBORw0KGgo="))
    }

    func testHTMLOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":2,"outputs":[{"output_type":"execute_result","execution_count":2,"metadata":{},"data":{"text/html":["<b>bold</b>"],"text/plain":["bold"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("<b>bold</b>"))
    }

    func testErrorOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"error","ename":"ValueError","evalue":"bad","traceback":["\\u001b[31mValueError\\u001b[0m: bad"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("cell-error"))
        XCTAssertTrue(html.contains("ValueError"))
    }

    func testLatexOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"execute_result","execution_count":null,"metadata":{},"data":{"text/latex":["$$E=mc^2$$"],"text/plain":["<IPython.core.display.Latex object>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("katex-latex"))
    }

    func testExecutionCountDisplayed() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["x=1"],"execution_count":42,"outputs":[]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("In [42]"))
    }

    func testInvalidJSONFallback() {
        let html = renderer.render(content: "not json at all", config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("notebook"))
        XCTAssertTrue(html.contains("Error")) // shows error message
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: FAIL — `NotebookRenderer` not found

- [x] **Step 3: Implement NotebookRenderer**

The NotebookRenderer parses ipynb JSON in Swift and generates static HTML for each cell. Markdown cells are placed as escaped text in `.markdown-cell-raw` divs — the browser-side JS then uses marked.js to render them. Code cell sources are HTML-escaped on the Swift side and placed in `<code>` elements for highlight.js. Output HTML from `text/html` mime type is inserted as-is (this is the same behavior as Jupyter itself — notebook HTML outputs are trusted content from the notebook author). Error tracebacks go through ANSIConverter which HTML-escapes before processing ANSI codes.

```swift
// Shared/Renderers/NotebookRenderer.swift
import Foundation

public final class NotebookRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        guard let data = content.data(using: .utf8),
              let notebook = try? JSONDecoder().decode(Notebook.self, from: data) else {
            return renderError("Error: Failed to parse notebook file.")
        }

        var cellsHTML = ""
        for cell in notebook.cells {
            switch cell.cellType {
            case .markdown:
                cellsHTML += renderMarkdownCell(cell)
            case .code:
                cellsHTML += renderCodeCell(cell)
            case .raw:
                cellsHTML += renderRawCell(cell)
            }
        }

        let body = """
        \(cellsHTML)
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            document.querySelectorAll('.markdown-cell-raw').forEach(function(el) {
                var raw = el.textContent;
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return hljs.highlightAuto(code).value;
                    },
                    gfm: true
                });
                el.innerHTML = marked.parse(raw);
                el.classList.remove('markdown-cell-raw');
                el.classList.add('markdown-cell');
            });

            document.querySelectorAll('.code-source code').forEach(function(el) {
                hljs.highlightElement(el);
            });

            document.querySelectorAll('.katex-latex').forEach(function(el) {
                try {
                    var math = el.textContent;
                    var displayMode = math.trim().startsWith('$$');
                    var cleaned = math.replace(/^\\$\\$|\\$\\$$/g, '').replace(/^\\$|\\$$/g, '').trim();
                    katex.render(cleaned, el, { displayMode: displayMode, throwOnError: false });
                } catch(e) {}
            });

            document.querySelectorAll('.markdown-cell').forEach(function(el) {
                var html = el.innerHTML;
                html = html.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(m, math) {
                    try { return katex.renderToString(math.trim(), { displayMode: true, throwOnError: false }); }
                    catch(e) { return m; }
                });
                html = html.replace(/\\$([^\\$\\n]+?)\\$/g, function(m, math) {
                    try { return katex.renderToString(math.trim(), { displayMode: false, throwOnError: false }); }
                    catch(e) { return m; }
                });
                el.innerHTML = html;
            });
        });
        </script>
        """

        return HTMLTemplate.wrap(body: body, rendererType: "notebook")
    }

    private func renderMarkdownCell(_ cell: Cell) -> String {
        let source = escapeHTML(cell.joinedSource)
        return """
        <div class="notebook-cell">
            <div class="markdown-cell-raw">\(source)</div>
        </div>
        """
    }

    private func renderCodeCell(_ cell: Cell) -> String {
        let execLabel: String
        if let count = cell.executionCount {
            execLabel = "In [\(count)]"
        } else {
            execLabel = "In [ ]"
        }
        let source = escapeHTML(cell.joinedSource)

        var html = """
        <div class="notebook-cell">
            <div class="cell-execution-count">\(execLabel)</div>
            <div class="cell-source code-source"><pre><code>\(source)</code></pre></div>
        """

        if let outputs = cell.outputs {
            for output in outputs {
                html += renderOutput(output)
            }
        }

        html += "</div>"
        return html
    }

    private func renderRawCell(_ cell: Cell) -> String {
        let source = escapeHTML(cell.joinedSource)
        return """
        <div class="notebook-cell">
            <div class="cell-output"><pre>\(source)</pre></div>
        </div>
        """
    }

    private func renderOutput(_ output: CellOutput) -> String {
        switch output {
        case .stream(let stream):
            let text = escapeHTML(stream.text.joined())
            return "<div class=\"cell-output\"><pre>\(text)</pre></div>"

        case .displayData(let display):
            return renderMimeData(display.data)

        case .executeResult(let result):
            return renderMimeData(result.data)

        case .error(let error):
            let traceback = error.traceback
                .map { ANSIConverter.toHTML($0) }
                .joined(separator: "\n")
            return "<div class=\"cell-output cell-error\"><pre>\(traceback)</pre></div>"
        }
    }

    private func renderMimeData(_ data: [String: MimeData]) -> String {
        // Priority order: image > html > latex > text
        if let png = data["image/png"] {
            return "<div class=\"cell-output\"><img src=\"data:image/png;base64,\(png.text)\"></div>"
        }
        if let jpeg = data["image/jpeg"] {
            return "<div class=\"cell-output\"><img src=\"data:image/jpeg;base64,\(jpeg.text)\"></div>"
        }
        // text/html output from notebooks is trusted content from the notebook
        // author (same trust model as Jupyter itself). CSP blocks external scripts.
        if let htmlData = data["text/html"] {
            return "<div class=\"cell-output\">\(htmlData.text)</div>"
        }
        if let latex = data["text/latex"] {
            return "<div class=\"cell-output\"><div class=\"katex-latex\">\(escapeHTML(latex.text))</div></div>"
        }
        if let plain = data["text/plain"] {
            return "<div class=\"cell-output\"><pre>\(escapeHTML(plain.text))</pre></div>"
        }
        return ""
    }

    private func renderError(_ message: String) -> String {
        let body = "<div class=\"cell-output cell-error\"><pre>\(escapeHTML(message))</pre></div>"
        return HTMLTemplate.wrap(body: body, rendererType: "notebook")
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: All 8 tests PASS

- [x] **Step 5: Commit**

```bash
git add Shared/Renderers/NotebookRenderer.swift Tests/NotebookRendererTests.swift
git commit -m "feat: add NotebookRenderer with full cell type and output support"
```

---

## Task 10: PreviewWebView — WKWebView with Security + Navigation Blocking

**Files:**
- Create: `Shared/WebView/PreviewWebView.swift`

This component is used by both the QuickLook extension and the host app's Preview tab.

- [x] **Step 1: Implement PreviewWebView**

```swift
// Shared/WebView/PreviewWebView.swift
import WebKit

public final class PreviewWebView: WKWebView {

    private let imageTimeoutSeconds: TimeInterval

    public init(frame: CGRect = .zero, imageTimeoutSeconds: TimeInterval = 3) {
        self.imageTimeoutSeconds = imageTimeoutSeconds

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let contentController = WKUserContentController()
        // Content Security Policy: only allow inline scripts (our bundled JS is
        // loaded via <script src> from local baseURL), inline styles, and images
        // from data: URIs and HTTP/HTTPS. Blocks external JS/CSS/iframes.
        let cspScript = WKUserScript(
            source: """
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' blob:; img-src data: http: https:; font-src data:;";
            document.head.prepend(meta);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(cspScript)
        config.userContentController = contentController

        super.init(frame: frame, configuration: config)

        self.navigationDelegate = self
        self.setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func loadHTML(_ html: String, resourcesURL: URL?) {
        if let baseURL = resourcesURL {
            loadHTMLString(html, baseURL: baseURL)
        } else {
            loadHTMLString(html, baseURL: nil)
        }
    }
}

extension PreviewWebView: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Allow initial HTML load and same-document navigation (anchors)
        if navigationAction.navigationType == .other {
            return .allow
        }
        // Block all user-initiated navigation (link clicks, form submissions, etc.)
        return .cancel
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        .allow
    }
}
```

- [x] **Step 2: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add Shared/WebView/PreviewWebView.swift
git commit -m "feat: add PreviewWebView with CSP, navigation blocking, and sandbox config"
```

---

## Task 11: Download JS Libraries

**Files:**
- Create: `Shared/Resources/js/marked.min.js`
- Create: `Shared/Resources/js/highlight.min.js`
- Create: `Shared/Resources/js/katex.min.js`
- Create: `Shared/Resources/css/katex.min.css`
- Create: `Shared/Resources/css/highlight-light.min.css`
- Create: `Shared/Resources/css/highlight-dark.min.css`
- Create: KaTeX font files

- [x] **Step 1: Download marked.js**

```bash
curl -L -o Shared/Resources/js/marked.min.js "https://cdn.jsdelivr.net/npm/marked/marked.min.js"
```

Verify: file exists and is ~50KB+

- [x] **Step 2: Download highlight.js with common languages**

```bash
curl -L -o Shared/Resources/js/highlight.min.js "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js"
curl -L -o Shared/Resources/css/highlight-light.min.css "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github.min.css"
curl -L -o Shared/Resources/css/highlight-dark.min.css "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github-dark.min.css"
```

- [x] **Step 3: Download KaTeX**

```bash
curl -L -o katex.tar.gz "https://github.com/KaTeX/KaTeX/releases/download/v0.16.11/katex.tar.gz"
tar xzf katex.tar.gz
cp katex/katex.min.js Shared/Resources/js/
cp katex/katex.min.css Shared/Resources/css/
mkdir -p Shared/Resources/css/fonts
cp katex/fonts/* Shared/Resources/css/fonts/
rm -rf katex katex.tar.gz
```

- [x] **Step 4: Verify all files exist**

```bash
ls -la Shared/Resources/js/
ls -la Shared/Resources/css/
ls -la Shared/Resources/css/fonts/
```

Expected: marked.min.js, highlight.min.js, katex.min.js, katex.min.css, highlight themes, KaTeX fonts all present

- [x] **Step 5: Commit**

```bash
git add Shared/Resources/
git commit -m "chore: bundle marked.js, highlight.js, and KaTeX libraries"
```

---

## Task 12: PreviewViewController — Extension Entry Point

**Files:**
- Modify: `QuickLookExtension/PreviewViewController.swift`

- [x] **Step 1: Implement PreviewViewController**

```swift
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
        let content = try String(contentsOf: url, encoding: .utf8)
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

        let resourcesURL = Bundle(for: Self.self).resourceURL
            ?? Bundle(for: type(of: self)).bundleURL

        await MainActor.run {
            webView.loadHTML(html, resourcesURL: resourcesURL)
        }
    }
}
```

- [x] **Step 2: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add QuickLookExtension/PreviewViewController.swift
git commit -m "feat: implement PreviewViewController with file routing to renderers"
```

---

## Task 13: Host App — App.swift with TabView + Placeholder Views

**Files:**
- Modify: `AllYouNeedQuickLook/App.swift`
- Create: `AllYouNeedQuickLook/Views/WelcomeView.swift` (placeholder)
- Create: `AllYouNeedQuickLook/Views/SettingsView.swift` (placeholder)
- Create: `AllYouNeedQuickLook/Views/PreviewView.swift` (placeholder)

- [x] **Step 1: Implement App with TabView and placeholder views**

```swift
// AllYouNeedQuickLook/App.swift
import SwiftUI

@main
struct AllYouNeedQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                WelcomeView()
                    .tabItem {
                        Label("Welcome", systemImage: "hand.wave")
                    }
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                PreviewView()
                    .tabItem {
                        Label("Preview", systemImage: "eye")
                    }
            }
            .frame(minWidth: 700, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
```

```swift
// AllYouNeedQuickLook/Views/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        Text("Welcome — placeholder")
    }
}
```

```swift
// AllYouNeedQuickLook/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings — placeholder")
    }
}
```

```swift
// AllYouNeedQuickLook/Views/PreviewView.swift
import SwiftUI

struct PreviewView: View {
    var body: some View {
        Text("Preview — placeholder")
    }
}
```

- [x] **Step 2: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add AllYouNeedQuickLook/App.swift AllYouNeedQuickLook/Views/
git commit -m "feat: add host app shell with TabView and placeholder views"
```

---

## Task 14: Host App — WelcomeView

**Files:**
- Modify: `AllYouNeedQuickLook/Views/WelcomeView.swift`

- [x] **Step 1: Implement WelcomeView**

```swift
// AllYouNeedQuickLook/Views/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("All You Need QuickLook")
                    .font(.largeTitle.bold())
                Text("Preview Markdown, text files, and Jupyter Notebooks in Finder.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Label("Markdown (.md) — rendered with syntax highlighting and math", systemImage: "doc.richtext")
                Label("Text & Logs (.txt, .log, ...) — configurable formatting", systemImage: "doc.text")
                Label("Jupyter Notebooks (.ipynb) — full cell rendering", systemImage: "terminal")
            }
            .font(.body)
            .padding(.horizontal, 40)

            Divider().padding(.horizontal, 60)

            VStack(spacing: 12) {
                Text("Enable the QuickLook Extension")
                    .font(.headline)

                Text("System Settings > Privacy & Security > Extensions > Quick Look")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open System Settings") {
                    openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [x] **Step 2: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add AllYouNeedQuickLook/Views/WelcomeView.swift
git commit -m "feat: implement WelcomeView with extension activation guide"
```

---

## Task 15: Host App — SettingsView

**Files:**
- Modify: `AllYouNeedQuickLook/Views/SettingsView.swift`

- [x] **Step 1: Implement SettingsView**

```swift
// AllYouNeedQuickLook/Views/SettingsView.swift
import SwiftUI
import Shared

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var newExtension = ""
    @State private var saveError: String?
    private let loader = ConfigLoader()

    init() {
        let loaded = ConfigLoader().load()
        _config = State(initialValue: loaded)
    }

    var body: some View {
        Form {
            Section("Global Settings") {
                TextField("Font Family", text: $config.global.fontFamily)
                Stepper("Font Size: \(config.global.fontSize)", value: $config.global.fontSize, in: 8...36)
                HStack {
                    Text("Line Height:")
                    Slider(value: $config.global.lineHeight, in: 1.0...3.0, step: 0.1)
                    Text(String(format: "%.1f", config.global.lineHeight))
                        .monospacedDigit()
                }
                Toggle("Show Line Numbers", isOn: $config.global.showLineNumbers)
                Stepper("Image Timeout: \(config.global.imageTimeoutSeconds)s",
                        value: $config.global.imageTimeoutSeconds, in: 1...30)
            }

            Section("File Type Settings") {
                ForEach(sortedFileTypes, id: \.key) { entry in
                    DisclosureGroup(entry.key) {
                        fileTypeEditor(for: entry.key)
                    }
                }

                HStack {
                    TextField("Add extension (e.g. yaml)", text: $newExtension)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let ext = newExtension.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !ext.isEmpty else { return }
                        if config.fileTypes == nil { config.fileTypes = [:] }
                        // Assigning unconditionally would overwrite an existing
                        // entry — typing "log" would wipe its level patterns.
                        guard config.fileTypes?[ext] == nil else {
                            newExtension = ""
                            return
                        }
                        config.fileTypes?[ext] = FileTypeConfig()
                        newExtension = ""
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                HStack {
                    Button("Reset to Default") {
                        // The default is the bundled default-config.json, not
                        // `AppConfig()` — that one has no fileTypes at all, and
                        // saving it would drop the log level patterns for good.
                        config = ConfigLoader.bundledDefault()
                        save()
                    }
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(
            "Could not save settings",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var sortedFileTypes: [(key: String, value: FileTypeConfig)] {
        (config.fileTypes ?? [:]).sorted { $0.key < $1.key }
    }

    @ViewBuilder
    private func fileTypeEditor(for ext: String) -> some View {
        let binding = Binding<FileTypeConfig>(
            get: { config.fileTypes?[ext] ?? FileTypeConfig() },
            set: { config.fileTypes?[ext] = $0 }
        )

        Toggle("Syntax Highlight", isOn: Binding(
            get: { binding.wrappedValue.syntaxHighlight ?? false },
            set: { binding.wrappedValue.syntaxHighlight = $0 }
        ))

        if binding.wrappedValue.syntaxHighlight == true {
            TextField("Language (e.g. xml, yaml)", text: Binding(
                get: { binding.wrappedValue.syntaxLanguage ?? "" },
                set: { binding.wrappedValue.syntaxLanguage = $0.isEmpty ? nil : $0 }
            ))
        }

        Toggle("Show Line Numbers", isOn: Binding(
            get: { binding.wrappedValue.showLineNumbers ?? config.global.showLineNumbers },
            set: { binding.wrappedValue.showLineNumbers = $0 }
        ))

        HStack {
            Spacer()
            Button("Remove", role: .destructive) {
                config.fileTypes?.removeValue(forKey: ext)
            }
            .foregroundStyle(.red)
        }
    }

    /// The only persistence path in the app, Reset included. Swallowing the
    /// error here would show a Save that appears to have worked while the
    /// extension goes on reading the old file — or, if the App Group container
    /// is unavailable, a file in a temporary directory that it never reads.
    private func save() {
        do {
            try loader.save(config)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
```

- [x] **Step 2: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 3: Commit**

```bash
git add AllYouNeedQuickLook/Views/SettingsView.swift
git commit -m "feat: implement SettingsView with global and per-extension config editor"
```

---

## Task 16: Host App — PreviewView with Sample Files

**Files:**
- Modify: `AllYouNeedQuickLook/Views/PreviewView.swift`
- Create: `AllYouNeedQuickLook/Views/PreviewWebViewRepresentable.swift`
- Create: `AllYouNeedQuickLook/SampleFiles/sample.md`
- Create: `AllYouNeedQuickLook/SampleFiles/sample.txt`
- Create: `AllYouNeedQuickLook/SampleFiles/sample.log`
- Create: `AllYouNeedQuickLook/SampleFiles/sample.ipynb`

- [x] **Step 1: Create sample files**

`AllYouNeedQuickLook/SampleFiles/sample.md`:

````markdown
# Sample Markdown

## Code Block

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
```

## Table

| Feature | Status |
|---------|--------|
| Markdown | Supported |
| Notebooks | Supported |
| Plain Text | Supported |

## Math

Inline: $E = mc^2$

Block:

$$\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}$$

## Formatting

**Bold**, *italic*, ~~strikethrough~~, and `inline code`.

> A blockquote for testing.

- Item 1
- Item 2
  - Nested item
````

`AllYouNeedQuickLook/SampleFiles/sample.txt`:

```
This is a plain text file for testing QuickLook preview.

It demonstrates basic text rendering with configurable formatting.
Line numbers, font family, font size, and line height can all be
customized through the Settings tab.

    Indented text should preserve its whitespace.

Special characters: <html> & "quotes"
```

`AllYouNeedQuickLook/SampleFiles/sample.log`:

```
2026-03-30 10:00:01 INFO  Application started successfully
2026-03-30 10:00:02 DEBUG Loading configuration from /etc/app/config.yaml
2026-03-30 10:00:03 INFO  Connected to database (pool_size=10)
2026-03-30 10:00:15 WARN  Slow query detected (2340ms): SELECT * FROM users WHERE ...
2026-03-30 10:00:30 ERROR Failed to process request: timeout after 30s
2026-03-30 10:00:30 ERROR Stack trace:
  at RequestHandler.process(RequestHandler.swift:142)
  at Server.handleConnection(Server.swift:89)
2026-03-30 10:00:31 INFO  Retrying request (attempt 2/3)
2026-03-30 10:00:32 WARN  Memory usage above 80% threshold (82.3%)
2026-03-30 10:00:45 FATAL Unrecoverable error: disk full
2026-03-30 10:00:45 CRITICAL Shutting down gracefully
```

`AllYouNeedQuickLook/SampleFiles/sample.ipynb`:

```json
{
  "nbformat": 4,
  "nbformat_minor": 5,
  "metadata": {
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    }
  },
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {},
      "source": ["# Sample Notebook\n", "\n", "This notebook demonstrates **QuickLook** rendering of `.ipynb` files.\n", "\n", "Inline math: $E = mc^2$"]
    },
    {
      "cell_type": "code",
      "metadata": {},
      "source": ["import numpy as np\n", "\n", "x = np.linspace(0, 2 * np.pi, 100)\n", "y = np.sin(x)\n", "print(f'Generated {len(x)} points')"],
      "execution_count": 1,
      "outputs": [
        {
          "output_type": "stream",
          "name": "stdout",
          "text": ["Generated 100 points\n"]
        }
      ]
    },
    {
      "cell_type": "code",
      "metadata": {},
      "source": ["# This cell shows an error output\n", "result = 1 / 0"],
      "execution_count": 2,
      "outputs": [
        {
          "output_type": "error",
          "ename": "ZeroDivisionError",
          "evalue": "division by zero",
          "traceback": [
            "\u001b[0;31m---------------------------------------------------------------------------\u001b[0m",
            "\u001b[0;31mZeroDivisionError\u001b[0m                         Traceback (most recent call last)",
            "Cell \u001b[0;32mIn[2], line 2\u001b[0m\n\u001b[1;32m      1\u001b[0m \u001b[38;5;66;03m# This cell shows an error output\u001b[0m\n\u001b[0;32m----> 2\u001b[0m result \u001b[38;5;241m=\u001b[0m \u001b[38;5;241;43m1\u001b[0m \u001b[38;5;241;43m/\u001b[0m \u001b[38;5;241;43m0\u001b[0m\n",
            "\u001b[0;31mZeroDivisionError\u001b[0m: division by zero"
          ]
        }
      ]
    },
    {
      "cell_type": "code",
      "metadata": {},
      "source": ["from IPython.display import HTML\n", "HTML('<b>Bold HTML output</b>')"],
      "execution_count": 3,
      "outputs": [
        {
          "output_type": "execute_result",
          "execution_count": 3,
          "metadata": {},
          "data": {
            "text/html": ["<b>Bold HTML output</b>"],
            "text/plain": ["<IPython.core.display.HTML object>"]
          }
        }
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {},
      "source": ["## Block Math\n", "\n", "$$\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}$$"]
    }
  ]
}
```

- [x] **Step 2: Create PreviewWebViewRepresentable**

```swift
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
```

- [x] **Step 3: Implement PreviewView**

```swift
// AllYouNeedQuickLook/Views/PreviewView.swift
import SwiftUI
import Shared

struct PreviewView: View {

    struct SampleFile: Identifiable, Hashable {
        let id: String
        let name: String
        let ext: String
    }

    private let samples: [SampleFile] = [
        SampleFile(id: "md", name: "sample.md", ext: "md"),
        SampleFile(id: "txt", name: "sample.txt", ext: "txt"),
        SampleFile(id: "log", name: "sample.log", ext: "log"),
        SampleFile(id: "ipynb", name: "sample.ipynb", ext: "ipynb"),
    ]

    @State private var selectedSample: SampleFile?

    /// The rendered document, recomputed when the selection changes.
    ///
    /// Rendering inside `body` re-read the sample from disk, re-read
    /// `config.json` from the App Group and rebuilt the whole ~475 KB template
    /// on *every* body evaluation, handing the web view a fresh string each
    /// time. Doing it here means one render per selection.
    @State private var renderedHTML: String?

    private static let resourcesURL = Bundle(for: ConfigLoader.self).resourceURL

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSample) {
                ForEach(samples) { sample in
                    Label(sample.name, systemImage: iconForExtension(sample.ext))
                        .tag(sample)
                }
            }
            .navigationTitle("Samples")
        } detail: {
            if let html = renderedHTML {
                PreviewWebViewRepresentable(html: html, resourcesURL: Self.resourcesURL)
            } else {
                ContentUnavailableView(
                    "Select a Sample File",
                    systemImage: "doc",
                    description: Text("Choose a file from the sidebar to preview.")
                )
            }
        }
        .onChange(of: selectedSample) { _, sample in
            renderedHTML = sample.map(Self.render)
        }
    }

    private static func render(_ sample: SampleFile) -> String {
        let content = loadSampleContent(sample.name)
        let config = ConfigLoader().load()
        let renderer: Renderer = switch sample.ext {
        case "md", "markdown": MarkdownRenderer()
        case "ipynb": NotebookRenderer()
        default: PlainTextRenderer()
        }
        return renderer.render(content: content, config: config, fileExtension: sample.ext)
    }

    private static func loadSampleContent(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(
                    forResource: (name as NSString).deletingPathExtension,
                    withExtension: (name as NSString).pathExtension
                ),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: Could not load \(name)"
        }
        return content
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "md": return "doc.richtext"
        case "txt": return "doc.text"
        case "log": return "terminal"
        case "ipynb": return "tablecells"
        default: return "doc"
        }
    }
}
```

- [x] **Step 4: Verify build**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [x] **Step 5: Commit**

```bash
git add AllYouNeedQuickLook/Views/ AllYouNeedQuickLook/SampleFiles/
git commit -m "feat: implement PreviewView with bundled sample files and live rendering"
```

---

## Task 17: End-to-End Build and Manual Verification

- [x] **Step 1: Run all unit tests**

```bash
xcodebuild test -project AllYouNeedQuickLook.xcodeproj -scheme Tests -destination "platform=macOS"
```

Expected: `** TEST SUCCEEDED **` with 0 failures. The count grows as tests are added — 97 as of the host-app UI branch — so read the failure count, not the total.

- [x] **Step 2: Build release archive**

```bash
xcodebuild -project AllYouNeedQuickLook.xcodeproj -scheme AllYouNeedQuickLook -configuration Release -destination "platform=macOS" build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual test checklist** — **sub-items 1, 2 and 3 done; sub-item 4
  (dark mode) is left to the repository owner.**

  1, 2 and 3 were driven against the Release build and screenshotted: Welcome tab,
  Settings tab (including "Reset to Default", after which `log` and `txt` are still
  listed), and all four samples in the Preview tab — highlighted markdown fence,
  inline and block KaTeX, log level colours, notebook cells with the sine PNG and
  the ANSI traceback.

  Sub-item 4 asks for the machine's appearance to be toggled, which is a system
  setting, so an agent does not perform it — same rule as step 4 below.

Open the built app and verify:

1. **Welcome tab** — shows activation instructions, "Open System Settings" button works
2. **Settings tab** — can modify font size, toggle line numbers, add/remove file types, save works
3. **Preview tab** — select each sample file:
   - `sample.md`: headings, code highlighting, table, math formulas render correctly
   - `sample.txt`: plain text with monospace font, line numbers if enabled
   - `sample.log`: ERROR (red), WARN (orange), INFO (blue) highlighted
   - `sample.ipynb`: markdown cell, code cells with highlighting, error traceback with colors, HTML output
4. **Dark mode** — toggle system appearance, verify all previews switch themes

- [ ] **Step 4: Test QuickLook extension** — **deferred to the repository owner.** This
  step changes the machine's system settings, so an agent must not perform it or tick it.

  The host app's Preview tab exercises `Shared/` (renderers, template, `PreviewWebView`)
  but **not** `PreviewViewController`, `QLSupportedContentTypes`, or the
  `org.jupyter.notebook` exported UTType — nothing else covers those.

1. Enable extension in System Settings > Extensions > Quick Look
2. In Finder, select a `.md` file and press Space
3. Verify rendered markdown appears in QuickLook panel
4. Repeat with `.txt`, `.log`, and `.ipynb` files

- [x] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: verify end-to-end build and all tests pass"
```
