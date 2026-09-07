// Shared/Renderers/HTMLTemplate.swift
import Foundation

public enum HTMLTemplate {

    public static let scriptNoncePlaceholder = "__AYNQL_SCRIPT_NONCE__"

    public static func wrap(
        body: String,
        rendererType: String,
        customCSS: String = ""
    ) -> String {
        let scriptNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let trustedBody = body.replacingOccurrences(of: scriptNoncePlaceholder, with: scriptNonce)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'nonce-\(scriptNonce)'; style-src 'self' 'unsafe-inline'; img-src data: quicklook-image:; font-src data: 'self'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
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
        <link rel="stylesheet" href="katex.min.css">
        <link rel="stylesheet" href="highlight-light.min.css" media="(prefers-color-scheme: light)">
        <link rel="stylesheet" href="highlight-dark.min.css" media="(prefers-color-scheme: dark)">
        <script src="marked.min.js"></script>
        <script src="highlight.min.js"></script>
        <script src="katex.min.js"></script>
        </head>
        <body class="\(rendererType)">
        \(trustedBody)
        <script nonce="\(scriptNonce)">
        document.addEventListener('DOMContentLoaded', function() {
            document.addEventListener('click', function(event) {
                var anchor = event.target.closest('a[href^="#"]');
                if (!anchor) {
                    return;
                }
                event.preventDefault();
                var fragment = anchor.getAttribute('href');
                var targetID;
                try {
                    targetID = decodeURIComponent(fragment.slice(1));
                } catch (error) {
                    return;
                }
                var target = document.getElementById(targetID);
                history.replaceState(null, '', document.URL.split('#')[0] + fragment);
                if (target) {
                    target.scrollIntoView();
                }
            });

            document.querySelectorAll('img[src]').forEach(function(image) {
                var source;
                try {
                    source = new URL(image.getAttribute('src'), document.baseURI);
                } catch (error) {
                    return;
                }
                if (source.protocol !== 'http:' && source.protocol !== 'https:') {
                    return;
                }

                image.addEventListener('error', function() {
                    var placeholder = document.createElement('div');
                    placeholder.className = 'placeholder-image';
                    placeholder.textContent = 'Image unavailable';
                    image.replaceWith(placeholder);
                }, { once: true });
                image.src = 'quicklook-image://fetch/?url=' + encodeURIComponent(source.href);
            });
            document.documentElement.dataset.quicklookReady = 'true';
        });
        </script>
        </body>
        </html>
        """
    }
}
