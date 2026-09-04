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
            marked.setOptions({ gfm: true, breaks: false });
            var container = document.getElementById('markdown-content');
            container.innerHTML = marked.parse(raw);

            renderMathInElement(container);
            highlightCodeBlocks(container);
        });

        // marked dropped its `highlight` option in v5 and the bundled build is
        // v15, so passing one to setOptions silently did nothing and every code
        // fence rendered unhighlighted. Highlighting is driven here instead,
        // the same way the notebook renderer drives it.
        //
        // Runs after the math pass, whose innerHTML round-trip would otherwise
        // re-parse these spans. hljs.highlightElement reads the element's
        // textContent and writes back its own escaped markup, so nothing that
        // marked already escaped is reintroduced to the DOM as raw source.
        function highlightCodeBlocks(container) {
            var blocks = container.querySelectorAll('pre code');
            for (var i = 0; i < blocks.length; i++) {
                try { hljs.highlightElement(blocks[i]); } catch (e) {}
            }
        }

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
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let pattern = try! NSRegularExpression(
            pattern: "</script(?=[\\s>/]|$)",
            options: .caseInsensitive
        )
        let range = NSRange(escaped.startIndex..., in: escaped)
        return pattern.stringByReplacingMatches(
            in: escaped,
            range: range,
            withTemplate: "<\\\\/script"
        )
    }
}
