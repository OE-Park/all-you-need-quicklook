// Shared/Renderers/PlainTextRenderer.swift
import Foundation

public final class PlainTextRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
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
                resolved: resolved, customCSS: customCSS
            )
        }

        let processedLines = lines.enumerated().map { index, line in
            let escapedLine = applyLogPatterns(
                escapeHTML(line), patterns: resolved.logLevelPatterns
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

    private func renderWithSyntaxHighlight(
        content: String, language: String,
        resolved: ResolvedFileTypeConfig, customCSS: String
    ) -> String {
        let contentString = javaScriptString(content)
        let languageString = javaScriptString(language)
        let languageClass = escapeHTML(language)
        let body = """
        <pre class="plaintext-content"><code id="code-content" class="language-\(languageClass)"></code></pre>
        <script nonce="\(HTMLTemplate.scriptNoncePlaceholder)">
        document.addEventListener('DOMContentLoaded', function() {
            var raw = \(contentString);
            var result = hljs.highlight(raw, { language: \(languageString) });
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
                    in: range, with: "<span class=\"\(cssClass)\">\(matched)</span>"
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

    private func javaScriptString(_ string: String) -> String {
        let data = try! JSONEncoder().encode(string)
        return String(decoding: data, as: UTF8.self)
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
