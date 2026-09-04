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
        img { max-width: 100%; height: auto; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
        th { background: var(--code-bg); }
        .log-error { color: var(--error-text); font-weight: 600; }
        .log-warn { color: var(--warn-text); font-weight: 600; }
        .log-info { color: var(--info-text); }
        .log-debug { color: var(--debug-text); }
        .line-number {
            display: inline-block; width: 4em; text-align: right;
            padding-right: 1em; color: var(--line-number);
            user-select: none; -webkit-user-select: none;
        }
        .notebook-cell { margin-bottom: 16px; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
        .cell-source { background: var(--cell-bg); padding: 12px 16px; }
        .cell-output { background: var(--output-bg); padding: 12px 16px; border-top: 1px solid var(--border); }
        .cell-output pre { background: transparent; padding: 0; border-radius: 0; }
        .cell-error { background: var(--error-bg); }
        .cell-execution-count { font-size: 11px; color: var(--line-number); padding: 4px 16px 0; }
        .markdown-cell { padding: 16px; }
        .markdown-cell h1, .markdown-cell h2, .markdown-cell h3,
        .markdown-cell h4, .markdown-cell h5, .markdown-cell h6 { margin-top: 1em; margin-bottom: 0.5em; }
        .markdown-cell p { margin: 0.5em 0; }
        .markdown-cell ul, .markdown-cell ol { padding-left: 2em; }
        .placeholder-image {
            background: var(--code-bg); border: 1px dashed var(--border);
            border-radius: 4px; padding: 20px; text-align: center;
            color: var(--line-number); font-size: 12px;
        }
        \(customCSS)
        </style>
        <style>
        \(katexCSS)
        </style>
        <style media="(prefers-color-scheme: light)">
        \(highlightLightCSS)
        </style>
        <style media="(prefers-color-scheme: dark)">
        \(highlightDarkCSS)
        </style>
        <script>
        \(markedJS)
        </script>
        <script>
        \(highlightJS)
        </script>
        <script>
        \(katexJS)
        </script>
        </head>
        <body class="\(rendererType)">
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Bundled libraries

    /// The bundled libraries are inlined into the document rather than linked
    /// with `<script src>` / `<link href>`.
    ///
    /// `PreviewWebView` hands the document to WebKit via
    /// `loadHTMLString(_:baseURL:)`. That document gets an opaque origin and
    /// WebKit grants it no read access to the file:// `baseURL` directory, so
    /// *every* relative subresource fails to load — verified to fail with the
    /// Content Security Policy removed entirely, and with `'self'` and `file:`
    /// added to it. Inlining is the only form that loads, and it also makes the
    /// intended inline-only policy literally true.
    ///
    /// Read once per process: the payload is ~470 KB and identical for every
    /// preview.
    static let katexCSS = bundledCSS("katex.min")
    static let highlightLightCSS = bundledCSS("highlight-light.min")
    static let highlightDarkCSS = bundledCSS("highlight-dark.min")
    static let markedJS = bundledJS("marked.min")
    static let highlightJS = bundledJS("highlight.min")
    static let katexJS = bundledJS("katex.min")

    private final class BundleToken {}

    /// Text of a resource bundled in the Shared framework; empty when missing.
    private static func bundledResource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    /// CSS ready to drop inside a `<style>` element. `<style>` is RAWTEXT, so
    /// only a literal `</style` closes it; `<\/style` is the same sequence to a
    /// CSS string or identifier, where alone it could legally appear.
    private static func bundledCSS(_ name: String) -> String {
        bundledResource(name, "css")
            .replacingOccurrences(of: "</style", with: "<\\/style", options: [.caseInsensitive])
    }

    /// JavaScript ready to drop inside a `<script>` element. Only `</script`
    /// closes it (from the escaped and double-escaped script-data states too);
    /// `<\/script` is the same sequence inside any JS string or regex literal.
    private static func bundledJS(_ name: String) -> String {
        bundledResource(name, "js")
            .replacingOccurrences(of: "</script", with: "<\\/script", options: [.caseInsensitive])
    }
}
