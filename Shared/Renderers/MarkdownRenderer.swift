// Shared/Renderers/MarkdownRenderer.swift
import Foundation

public final class MarkdownRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String {
        let escapedContent = ScriptEscaping.forTemplateLiteral(content)
        let body = """
        <div id="markdown-content" class="markdown"></div>
        <script nonce="\(nonce)">
        document.addEventListener('DOMContentLoaded', function() {
            var raw = `\(escapedContent)`;
            marked.setOptions({ gfm: true, breaks: false });
            var container = document.getElementById('markdown-content');
            container.innerHTML = marked.parse(raw);

            renderPreviewMath(container);
            highlightCodeBlocks(container);
        });

        // marked dropped its `highlight` option in v5 and the bundled build is
        // v15, so passing one to setOptions silently did nothing and every code
        // fence rendered unhighlighted. Highlighting is driven here instead,
        // the same way the notebook renderer drives it.
        //
        // The math pass excludes code. hljs.highlightElement reads the element's
        // textContent and writes back its own escaped markup, so nothing that
        // marked already escaped is reintroduced to the DOM as raw source.
        function highlightCodeBlocks(container) {
            var blocks = container.querySelectorAll('pre code');
            for (var i = 0; i < blocks.length; i++) {
                try { hljs.highlightElement(blocks[i]); } catch (e) {}
            }
        }

        </script>
        """
        return HTMLTemplate.wrap(body: body, rendererType: "markdown", nonce: nonce, allowExternalImages: config.global.allowExternalImages)
    }
}
