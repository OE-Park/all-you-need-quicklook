// Shared/Renderers/PlainTextRenderer.swift
import Foundation

public final class PlainTextRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String {
        let resolved = config.resolvedConfig(for: fileExtension)
        let lines = content.components(separatedBy: "\n")

        let customCSS = """
        pre.plaintext-content {
            font-family: "\(escapeCSSString(resolved.fontFamily))", monospace;
            font-size: \(resolved.fontSize)px;
            line-height: \(resolved.lineHeight);
        }
        """

        if resolved.syntaxHighlight, let language = resolved.syntaxLanguage {
            return renderWithSyntaxHighlight(
                content: content, language: language,
                resolved: resolved, customCSS: customCSS, nonce: nonce
            )
        }

        let processedLines = lines.enumerated().map { index, line in
            let escapedLine = applyLogPatterns(
                HTMLEscaper.escape(line), patterns: resolved.logLevelPatterns
            )
            if resolved.showLineNumbers {
                let num = String(index + 1)
                return "<span class=\"line-number\">\(num)</span>\(escapedLine)"
            }
            return escapedLine
        }

        let body = "<pre class=\"plaintext-content\">\(processedLines.joined(separator: "\n"))</pre>"
        return HTMLTemplate.wrap(body: body, rendererType: "plaintext", nonce: nonce, customCSS: customCSS)
    }

    private func renderWithSyntaxHighlight(
        content: String, language: String,
        resolved: ResolvedFileTypeConfig, customCSS: String, nonce: String
    ) -> String {
        let escaped = ScriptEscaping.forTemplateLiteral(content)
        let escapedLanguage = ScriptEscaping.forSingleQuotedLiteral(language)
        let body = """
        <pre class="plaintext-content"><code id="code-content" class="language-\(HTMLEscaper.escape(language))"></code></pre>
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
                    in: range, with: "<span class=\"\(cssClass)\">\(matched)</span>"
                )
            }
        }
        return result
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
