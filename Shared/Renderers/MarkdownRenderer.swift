// Shared/Renderers/MarkdownRenderer.swift
import Foundation

public final class MarkdownRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        let escapedContent = escapeForJS(content)
        let body = """
        <div id="markdown-content" class="markdown"></div>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var raw = `\(escapedContent)`;
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
            .replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)
    }
}
