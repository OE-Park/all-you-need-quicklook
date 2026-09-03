// Shared/Renderers/MarkdownRenderer.swift
import Foundation

public final class MarkdownRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        let contentString = javaScriptString(content)
        let body = """
        <div id="markdown-content" class="markdown"></div>
        <script nonce="\(HTMLTemplate.scriptNoncePlaceholder)">
        document.addEventListener('DOMContentLoaded', function() {
            var raw = \(contentString);
            var escapeHTML = function(value) {
                return value.replace(/&/g, '&amp;')
                    .replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;')
                    .replace(/"/g, '&quot;')
                    .replace(/'/g, '&#39;');
            };
            var renderer = new marked.Renderer();
            renderer.html = function(token) {
                return escapeHTML(token.text);
            };
            marked.setOptions({
                renderer: renderer,
                gfm: true,
                breaks: false
            });
            var rendered = marked.parse(raw);
            document.getElementById('markdown-content').innerHTML = rendered;

            renderMathInElement(document.getElementById('markdown-content'));
            document.querySelectorAll('#markdown-content pre code').forEach(function(el) {
                hljs.highlightElement(el);
            });
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

    private func javaScriptString(_ string: String) -> String {
        let data = try! JSONEncoder().encode(string)
        return String(decoding: data, as: UTF8.self)
    }
}
