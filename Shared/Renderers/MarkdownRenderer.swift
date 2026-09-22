// Shared/Renderers/MarkdownRenderer.swift
import Foundation

public final class MarkdownRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String {
        let resolved = config.resolvedConfig(for: fileExtension)
        let escapedContent = ScriptEscaping.forTemplateLiteral(content)

        // Size and line height always follow the configuration. The family
        // does so only when this file type names one, because the *global*
        // default is "SF Mono" -- chosen for plain text and code, and never
        // for prose. Inheriting it here would silently set every markdown
        // document in a monospace face that nobody asked for.
        let explicitFamily = config.fileTypes?[fileExtension]?.fontFamily
        let familyRule = explicitFamily.map {
            "    font-family: \"\(CSSStringEscaper.escape($0))\", -apple-system, BlinkMacSystemFont, sans-serif;\n"
        } ?? ""

        let customCSS = """
        body.markdown {
        \(familyRule)    font-size: \(resolved.fontSize)px;
            line-height: \(resolved.lineHeight);
        }
        body.markdown pre, body.markdown pre code { font-size: \(resolved.fontSize)px; }
        """

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
                highlightBlock(blocks[i]);
            }
        }

        // The bundled highlight.js is the `common` build, so a fence can name a
        // language it has no grammar for -- dockerfile and terraform among the
        // usual ones. hljs.highlightElement only warns to the console and
        // leaves the block bare, which reads as "highlighting is broken".
        // Check first, fall back to detection, and mark the block when even
        // that is refused so the missing colour is explained rather than
        // silent.
        function highlightBlock(block) {
            var declared = '';
            var match = /(?:^|\\s)language-([^\\s]+)/.exec(block.className || '');
            if (match) { declared = match[1]; }

            try {
                if (declared && hljs.getLanguage(declared)) {
                    hljs.highlightElement(block);
                    return;
                }
                var result = hljs.highlightAuto(block.textContent);
                block.innerHTML = result.value;
                block.classList.add('hljs');
                if (declared) {
                    block.setAttribute('data-unhighlighted-language', declared);
                }
            } catch (e) {
                if (declared) {
                    block.setAttribute('data-unhighlighted-language', declared);
                }
            }
        }

        </script>
        """
        return HTMLTemplate.wrap(
            body: body, rendererType: "markdown", nonce: nonce,
            customCSS: customCSS, allowExternalImages: config.global.allowExternalImages
        )
    }
}
