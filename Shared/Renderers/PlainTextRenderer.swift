// Shared/Renderers/PlainTextRenderer.swift
import Foundation

public final class PlainTextRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String {
        let resolved = config.resolvedConfig(for: fileExtension)
        let preview = boundedPreview(content)
        let content = preview.text
        let lines = content.components(separatedBy: "\n")

        let customCSS = """
        pre.plaintext-content {
            font-family: "\(escapeCSSString(resolved.fontFamily))", monospace;
            font-size: \(resolved.fontSize)px;
            line-height: \(resolved.lineHeight);
        }
        pre.plaintext-content code { font: inherit; }
        .numbered-text { display: flex; align-items: flex-start; }
        .numbered-text .plaintext-content { flex: 1; min-width: 0; }
        pre.line-number-gutter {
            order: -1; flex-shrink: 0; padding-right: 0; user-select: none;
            font-family: "\(escapeCSSString(resolved.fontFamily))", monospace;
            font-size: \(resolved.fontSize)px; line-height: \(resolved.lineHeight);
        }
        """

        if resolved.syntaxHighlight, let language = resolved.syntaxLanguage {
            return renderWithSyntaxHighlight(
                content: content, language: language,
                resolved: resolved, customCSS: customCSS, nonce: nonce, notice: preview.notice
            )
        }

        let highlighter = resolved.logLevelPatterns.flatMap { $0.isEmpty ? nil : LogPatternHighlighter(patterns: $0) }
        let processedLines = lines.enumerated().map { index, line in
            let escapedLine = highlighter?.renderLine(line) ?? HTMLEscaper.escape(line)
            if resolved.showLineNumbers {
                let num = String(index + 1)
                return "<span class=\"line-number\">\(num)</span>\(escapedLine)"
            }
            return escapedLine
        }

        let skipped = highlighter?.skipped == true
            ? "<div class=\"placeholder-image highlight-skipped\">Some log highlighting was skipped because a pattern is unsupported or the preview limit was reached.</div>" : ""
        let body = "<pre class=\"plaintext-content\">\(processedLines.joined(separator: "\n"))</pre>\(skipped)\(preview.notice)"
        return HTMLTemplate.wrap(body: body, rendererType: "plaintext", nonce: nonce, customCSS: customCSS)
    }

    private func renderWithSyntaxHighlight(
        content: String, language: String,
        resolved: ResolvedFileTypeConfig, customCSS: String, nonce: String, notice: String
    ) -> String {
        let escaped = ScriptEscaping.forTemplateLiteral(content)
        let escapedLanguage = ScriptEscaping.forSingleQuotedLiteral(language)
        let gutter = resolved.showLineNumbers
            ? "<pre class=\"line-number-gutter\" aria-hidden=\"true\">" + content.components(separatedBy: "\n").indices.map {
                "<span class=\"line-number\">\($0 + 1)</span>"
            }.joined(separator: "\n") + "</pre>" : ""
        let body = """
        <div class="numbered-text">
        <pre class="plaintext-content"><code id="code-content" class="language-\(HTMLEscaper.escape(language))"></code></pre>
        \(gutter)
        </div>
        \(notice)
        <script nonce="\(nonce)">
        document.addEventListener('DOMContentLoaded', function() {
            var raw = `\(escaped)`;
            var result = hljs.getLanguage('\(escapedLanguage)')
                ? hljs.highlight(raw, { language: '\(escapedLanguage)' })
                : hljs.highlightAuto(raw);
            document.getElementById('code-content').innerHTML = result.value;
        });
        </script>
        """
        return HTMLTemplate.wrap(body: body, rendererType: "plaintext", nonce: nonce, customCSS: customCSS)
    }

    private func boundedPreview(_ content: String) -> (text: String, notice: String) {
        var scalars = String.UnicodeScalarView()
        var units = 0, lines = 1
        for scalar in content.unicodeScalars {
            let width = scalar.value > 0xffff ? 2 : 1
            if units + width > 262144 || (scalar == "\n" && lines == 10000) {
                return (String(scalars), "<div class=\"placeholder-image preview-truncated\">Preview truncated to 262,144 UTF-16 units or 10,000 lines. Open the file to read the rest.</div>")
            }
            scalars.append(scalar)
            units += width
            if scalar == "\n" { lines += 1 }
        }
        return (String(scalars), "")
    }

    private func escapeCSSString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "<", with: "\\3C ")
            .replacingOccurrences(of: "\n", with: "\\A ")
            .replacingOccurrences(of: "\r", with: "\\D ")
    }
}
