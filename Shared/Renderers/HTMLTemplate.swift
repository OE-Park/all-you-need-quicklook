// Shared/Renderers/HTMLTemplate.swift
import Foundation

public enum HTMLTemplate {

    /// Composes a complete preview document.
    ///
    /// `nonce` must be the same `PreviewWebView.makeNonce()` value that is
    /// passed to `PreviewWebView.loadHTML(_:resourcesURL:nonce:)` for this
    /// document. `script-src` names that nonce and nothing else, so an
    /// unstamped or mismatched `<script>` — including every one of the three
    /// bundled libraries below — simply does not run.
    public static func wrap(
        body: String,
        rendererType: String,
        nonce: String,
        customCSS: String = "",
        allowExternalImages: Bool = false
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta http-equiv="Content-Security-Policy" content="\(PreviewWebView.contentSecurityPolicy(nonce: nonce))">
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
            --muted: #57606a;
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
                --muted: #9198a1;
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

        /* The `*` reset above strips every block margin, and nothing else puts
           them back. marked emits plain semantic HTML, so without these rules
           headings, paragraphs and lists render flush against one another and
           list markers sit outside the content box. Both markdown surfaces --
           a standalone .md document (.markdown) and a notebook markdown cell
           (.markdown-cell) -- are listed together so the two cannot drift. */
        .markdown h1, .markdown h2, .markdown h3, .markdown h4, .markdown h5, .markdown h6,
        .markdown-cell h1, .markdown-cell h2, .markdown-cell h3,
        .markdown-cell h4, .markdown-cell h5, .markdown-cell h6 {
            margin-top: 1.5em; margin-bottom: 0.5em; line-height: 1.25;
        }
        .markdown > :first-child, .markdown-cell > :first-child { margin-top: 0; }
        .markdown h1, .markdown h2, .markdown-cell h1, .markdown-cell h2 {
            padding-bottom: 0.3em; border-bottom: 1px solid var(--border);
        }
        .markdown p, .markdown-cell p { margin: 0.8em 0; }
        .markdown ul, .markdown ol, .markdown-cell ul, .markdown-cell ol {
            padding-left: 2em; margin: 0.8em 0;
        }
        .markdown li, .markdown-cell li { margin: 0.25em 0; }
        .markdown li > ul, .markdown li > ol,
        .markdown-cell li > ul, .markdown-cell li > ol { margin: 0.25em 0; }
        /* --muted, not --line-number: a blockquote is body text, and the
           gutter grey is deliberately faint enough to fail contrast for it. */
        .markdown blockquote, .markdown-cell blockquote {
            margin: 1em 0; padding: 0 1em;
            border-left: 4px solid var(--border); color: var(--muted);
        }
        .markdown pre, .markdown-cell pre { margin: 1em 0; }
        /* hljs.highlightElement adds `hljs` to the `code`, and the theme gives
           that class its own background and `pre code.hljs` its own 1em
           padding -- inside a `pre` that already has both. Left alone a fenced
           block renders as a box within a box in a second colour. Only the
           container styling is dropped; the token colours are separate
           selectors and stay. */
        .markdown pre code.hljs, .markdown-cell pre code.hljs {
            background: transparent; padding: 0;
        }
        .markdown hr, .markdown-cell hr {
            margin: 1.5em 0; border: 0; height: 1px; background: var(--border);
        }
        /* `code` outside a `pre` is inline: give it a chip, but leave fenced
           blocks to the `pre` rule so they are not double-padded. */
        .markdown :not(pre) > code, .markdown-cell :not(pre) > code {
            background: var(--code-bg); border-radius: 4px;
            padding: 0.2em 0.4em; font-size: 0.9em;
        }
        .markdown img, .markdown-cell img { margin: 0.5em 0; }

        /* A fence whose language the bundled highlight.js does not carry.
           hljs only warns to the console and leaves the block bare, so the
           renderer marks it and the label says why it has no colour. */
        [data-unhighlighted-language]::before {
            content: "no highlighter for “" attr(data-unhighlighted-language) "”";
            display: block; margin-bottom: 8px;
            font-size: 11px; color: var(--muted);
        }
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
        <script nonce="\(nonce)">
        \(markedJS)
        </script>
        <script nonce="\(nonce)">
        \(highlightJS)
        </script>
        <script nonce="\(nonce)">
        \(katexJS)
        \(mathJS)
        </script>
        </head>
        <body class="\(rendererType)">
        \(body)
        <script nonce="\(nonce)">
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
                var remote = source.protocol === 'http:' || source.protocol === 'https:';
                if (!\(allowExternalImages ? "true" : "false") && (remote || source.protocol === 'quicklook-image:')) {
                    var blocked = document.createElement('div');
                    blocked.className = 'placeholder-image external-image-blocked';
                    blocked.textContent = 'External image blocked. Allow external images in Settings to load it.';
                    image.replaceWith(blocked);
                    return;
                }
                if (!remote) {
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
    static let katexCSS = bundledCSS("katex.min").replacingOccurrences(of: "url(fonts/", with: "url(quicklook-resource://bundle/")
    static let highlightLightCSS = bundledCSS("highlight-light.min")
    static let highlightDarkCSS = bundledCSS("highlight-dark.min")
    static let markedJS = bundledJS("marked.min")
    static let highlightJS = bundledJS("highlight.min")
    static let katexJS = bundledJS("katex.min")
    static let mathJS = bundledJS("render-math")

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

    /// JavaScript ready to drop inside a `<script>` element.
    ///
    /// Two sequences are neutralised, and both replacements are the same string
    /// to a JS string, template or regular-expression literal:
    ///
    /// - `</script` ends the element from the script-data state. `\/` is a legal
    ///   escape in every one of those contexts, unicode-mode regexes included.
    /// - `<!--` moves the tokenizer into script-data-escaped, and a later
    ///   `<script` with no intervening `-->` moves it into
    ///   script-data-double-escaped, where the element's real `</script>` no
    ///   longer closes it. `\x21` is used rather than `\!` because `\!` is not a
    ///   legal identity escape inside a unicode-mode regex literal.
    ///
    /// marked.min.js and highlight.min.js already contain `<!--` today (both
    /// closed, so neither is exploitable) — this keeps a library bump from
    /// making that matter.
    private static func bundledJS(_ name: String) -> String {
        bundledResource(name, "js")
            .replacingOccurrences(of: "</script", with: "<\\/script", options: [.caseInsensitive])
            .replacingOccurrences(of: "<!--", with: "<\\x21--")
    }
}
