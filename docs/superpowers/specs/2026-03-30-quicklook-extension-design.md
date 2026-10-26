# AllYouNeedQuickLook — Design Spec

**Date:** 2026-03-30
**Target:** macOS 15+ (Sequoia)
**Distribution:** Open source, GitHub Release (.dmg/.zip), Apple code signing + notarization planned

---

## Overview

A macOS QuickLook Preview Extension that renders Markdown, plain text/log files, and Jupyter Notebooks directly in Finder's Quick Look panel. All rendering flows through a single WKWebView-based HTML pipeline for consistency and maintainability.

---

## Architecture

### Rendering Pipeline

All file types follow the same path:

```
File received → Extension detection → Renderer selection → HTML generation → Template injection → WKWebView display
```

A single HTML template wraps all content. CSS variables control theming, and `prefers-color-scheme: dark` handles automatic dark mode switching.

### Project Structure

```
AllYouNeedQuickLook/
├── AllYouNeedQuickLook/          # Host app (macOS App, SwiftUI)
│   ├── App.swift
│   ├── Views/                    # Welcome, Settings, Preview tabs
│   ├── SampleFiles/              # Bundled samples (sample.md, .txt, .log, .ipynb)
│   └── Assets.xcassets
├── QuickLookExtension/           # QuickLook Preview Extension
│   ├── PreviewViewController.swift
│   ├── Info.plist                # QLSupportedContentTypes
│   ├── Renderers/
│   │   ├── MarkdownRenderer.swift
│   │   ├── PlainTextRenderer.swift
│   │   └── NotebookRenderer.swift
│   ├── WebView/
│   │   ├── WebViewPreview.swift  # WKWebView setup + timeout control
│   │   └── Templates/           # HTML templates, CSS
│   ├── Resources/
│   │   ├── js/                   # marked.js, highlight.js, KaTeX
│   │   └── css/                  # Theme CSS (light/dark)
│   └── Config/
│       ├── ConfigLoader.swift    # JSON config loader
│       └── default-config.json   # Default formatting config
└── Shared/                       # Shared between host app and extension
    ├── Models/
    └── ConfigSchema.swift        # JSON config schema definition
```

---

## Renderers

### MarkdownRenderer

- Injects raw markdown content into the HTML template
- `marked.js` parses markdown → `highlight.js` highlights code blocks
- KaTeX renders LaTeX math expressions
- Handles standalone `.md` files (ipynb markdown cells share the same marked.js pipeline in the browser, but are orchestrated by NotebookRenderer)

### PlainTextRenderer

- Looks up per-extension formatting from JSON config
- Wraps text in `<pre>` block with CSS variables for font, size, line height
- For `.log` files: the bundled bounded compiler/matcher runs in JavaScriptCore over original source lines; escaped source slices receive deterministic error>warn>info>debug styling. Unsupported patterns and exhausted budgets leave readable text with a notice.
- Plain-text preview output is limited to 262,144 UTF-16 units or 10,000 lines, preserving Unicode scalar boundaries and showing a truncation notice. Syntax-highlighted code inherits the selected font and has an independent line-number gutter.
- Falls back to global defaults for unconfigured extensions

### NotebookRenderer

- Parses `.ipynb` JSON structure in Swift
- Iterates cells and converts each to HTML:
  - **Markdown cells:** Delegated to marked.js (same path as MarkdownRenderer)
  - **Code cells — source:** Wrapped in `<pre><code>` with highlight.js syntax highlighting
  - **Code cells — outputs:**
    - `text/plain` → `<pre>` block
    - `text/html` → rendered as untrusted markup under the nonce CSP; scripts and event handlers cannot execute
    - `image/png`, `image/jpeg` → base64 `<img>` tag
    - `text/latex` → KaTeX rendering
    - `error` → traceback with ANSI color codes converted to CSS

---

## External Image Loading

External images (`<img src="https://...">`) are supported with a 3-second timeout:

- Renderer JavaScript rewrites HTTP(S) image URLs to the private `quicklook-image:` scheme
- A `WKURLSchemeHandler` uses an ephemeral `URLSession` with `timeoutIntervalForRequest` and `timeoutIntervalForResource` set from configuration
- Both HTTP and HTTPS are allowed (`NSAppTransportSecurity` exception configured)
- On timeout: replaced with a placeholder image
- Non-2xx, non-image, oversized (over 25 MiB), and failed responses use the same placeholder path
- Non-image external resources (CSS, JS, iframe) are blocked

---

## JSON Configuration

Stored in the App Group container. Host app writes, extension reads.

### Schema

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
      "fontFamily": null,
      "fontSize": null,
      "lineHeight": null,
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
    },
    "plist": {
      "syntaxHighlight": true,
      "syntaxLanguage": "xml"
    }
  }
}
```

- Per-extension fields set to `null` inherit from `global`
- Users can add new extensions (e.g., `yaml`, `conf`) — they work immediately because `public.plain-text` UTType already covers them
- `syntaxLanguage` specifies the highlight.js language for syntax highlighting

---

## Host App

SwiftUI app with three tabs:

### 1. Welcome Tab
- App introduction + QuickLook extension activation instructions
- Deep link button to System Settings > Extensions
- Extension activation status indicator

### 2. Settings Tab
- GUI editor for JSON configuration
- Global formatting settings (font, size, line height, line numbers)
- Per-extension formatting list (add/edit/delete)
- Reset to Default button
- Auto-saves on change to App Group container

### 3. Preview Tab
- Sidebar: list of bundled sample files
  - `sample.md` — headings, code blocks, tables, math expressions
  - `sample.txt` — plain text
  - `sample.log` — log file with mixed log levels
  - `sample.ipynb` — code cells + markdown cells + image outputs
- Detail view: rendered preview using the same rendering code as the extension (via `Shared/`)

---

## Security & Sandbox

### Entitlements

**QuickLook Extension:**
- `com.apple.security.app-sandbox` = `true`
- `com.apple.security.network.client` = `true` (external image loading)
- `com.apple.security.application-groups` = `group.com.yohanpark.AllYouNeedQuickLook`

**Host App:**
- `com.apple.security.app-sandbox` = `true`
- `com.apple.security.network.client` = `true` (sandboxed WKWebView process support, including local sample previews)
- `com.apple.security.application-groups` = `group.com.yohanpark.AllYouNeedQuickLook`

### WKWebView Security

- External JavaScript execution blocked — only bundled JS allowed
- Inline renderer JavaScript requires a per-document CSP nonce; `script-src 'unsafe-inline'` is not used
- Bundled JS/CSS are inlined; only app-controlled scripts carry the document nonce
- Bundled fonts are served through the private `quicklook-resource://bundle` scheme
- External link navigation blocked (no page navigation from QuickLook)
- External images are blocked by default, including legacy configurations without `allowExternalImages`. Settings can explicitly enable them, with a notice that requests may contact internet or local network servers. The native loader enforces the choice even for document-authored `quicklook-image:` URLs; embedded data images remain supported. Opt-in requests retain the configurable timeout (default 3s) and 25 MiB response cap. Other external resources (CSS, JS, iframe) remain blocked.

### Info.plist — QLSupportedContentTypes

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>QLSupportedContentTypes</key>
        <array>
            <string>public.plain-text</string>
            <string>net.daringfireball.markdown</string>
            <string>org.jupyter.notebook</string>
        </array>
    </dict>
</dict>
```

- `public.plain-text` — covers txt, log, conf, yaml, plist, and other plain text formats
- `net.daringfireball.markdown` — dedicated UTType for .md files
- `org.jupyter.notebook` — dedicated UTType for .ipynb files; requires exported UTType declaration in Info.plist since this is not a system-defined UTType (`UTExportedTypeDeclarations` with `conformsTo: public.json`)

---

## Bundled JS Libraries

| Library | Purpose | Approximate Size |
|---------|---------|-----------------|
| marked.js | Markdown parsing | ~50 KB |
| highlight.js | Code syntax highlighting | ~30 KB (core) + language packs |
| KaTeX | LaTeX math rendering | ~300 KB (CSS + fonts + JS) |

All libraries are bundled in the extension, no CDN or external loading.

---

## Dark Mode

Automatic switching via CSS `prefers-color-scheme`:

```css
:root {
  --bg: #ffffff;
  --text: #1d1d1f;
  --code-bg: #f5f5f7;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1d1d1f;
    --text: #f5f5f7;
    --code-bg: #2c2c2e;
  }
}
```

All renderers use CSS variables, ensuring consistent theming across file types.

---

## Distribution

- **Phase 1:** GitHub Release with unsigned `.zip`/`.dmg` (users run `xattr -cr` to allow)
- **Phase 2:** Apple Developer Program enrollment → code signing + notarization for seamless installation
- Homebrew Cask registration considered for future
