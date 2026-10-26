// Shared/Renderers/NotebookRenderer.swift
import Foundation

public final class NotebookRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String {
        guard let data = content.data(using: .utf8),
              let notebook = try? JSONDecoder().decode(Notebook.self, from: data) else {
            return renderError("Error: Failed to parse notebook file.", nonce: nonce)
        }

        var cellsHTML = ""
        for cell in notebook.cells {
            switch cell.cellType {
            case .markdown:
                cellsHTML += renderMarkdownCell(cell)
            case .code:
                cellsHTML += renderCodeCell(cell)
            case .raw:
                cellsHTML += renderRawCell(cell)
            }
        }

        let body = """
        \(cellsHTML)
        <script nonce="\(nonce)">
        document.addEventListener('DOMContentLoaded', function() {
            marked.setOptions({ gfm: true });
            document.querySelectorAll('.markdown-cell-raw').forEach(function(el) {
                var raw = el.textContent;
                el.innerHTML = marked.parse(raw);
                el.classList.remove('markdown-cell-raw');
                el.classList.add('markdown-cell');
            });


            document.querySelectorAll('.katex-latex').forEach(function(el) {
                try {
                    var math = el.textContent;
                    var displayMode = math.trim().startsWith('$$');
                    var cleaned = math.replace(/^\\$\\$|\\$\\$$/g, '').replace(/^\\$|\\$$/g, '').trim();
                    katex.render(cleaned, el, { displayMode: displayMode, throwOnError: false });
                } catch(e) {}
            });

            document.querySelectorAll('.markdown-cell').forEach(function(el) {
                renderPreviewMath(el);
            });
            document.querySelectorAll('.code-source code, .markdown-cell pre code').forEach(function(el) {
                hljs.highlightElement(el);
            });
        });
        </script>
        """

        return HTMLTemplate.wrap(body: body, rendererType: "notebook", nonce: nonce, allowExternalImages: config.global.allowExternalImages)
    }

    private func renderMarkdownCell(_ cell: Cell) -> String {
        let source = HTMLEscaper.escape(cell.joinedSource)
        return """
        <div class="notebook-cell">
            <div class="markdown-cell-raw">\(source)</div>
        </div>
        """
    }

    private func renderCodeCell(_ cell: Cell) -> String {
        let execLabel: String
        if let count = cell.executionCount {
            execLabel = "In [\(count)]"
        } else {
            execLabel = "In [ ]"
        }
        let source = HTMLEscaper.escape(cell.joinedSource)

        var html = """
        <div class="notebook-cell">
            <div class="cell-execution-count">\(execLabel)</div>
            <div class="cell-source code-source"><pre><code>\(source)</code></pre></div>
        """

        if let outputs = cell.outputs {
            for output in outputs {
                html += renderOutput(output)
            }
        }

        html += "</div>"
        return html
    }

    private func renderRawCell(_ cell: Cell) -> String {
        let source = HTMLEscaper.escape(cell.joinedSource)
        return """
        <div class="notebook-cell">
            <div class="cell-output"><pre>\(source)</pre></div>
        </div>
        """
    }

    private func renderOutput(_ output: CellOutput) -> String {
        switch output {
        case .stream(let stream):
            let text = HTMLEscaper.escape(stream.text.joined())
            return "<div class=\"cell-output\"><pre>\(text)</pre></div>"

        case .displayData(let display):
            return renderMimeData(display.data)

        case .executeResult(let result):
            return renderMimeData(result.data)

        case .error(let error):
            let traceback = error.traceback
                .map { ANSIConverter.toHTML($0) }
                .joined(separator: "\n")
            return "<div class=\"cell-output cell-error\"><pre>\(traceback)</pre></div>"
        }
    }

    private func renderMimeData(_ data: [String: MimeData]) -> String {
        // Priority order: image > html > latex > text
        if let png = data["image/png"] {
            return "<div class=\"cell-output\"><img src=\"data:image/png;base64,\(HTMLEscaper.escape(png.text))\"></div>"
        }
        if let jpeg = data["image/jpeg"] {
            return "<div class=\"cell-output\"><img src=\"data:image/jpeg;base64,\(HTMLEscaper.escape(jpeg.text))\"></div>"
        }
        // text/html output is the one place a notebook's own markup is handed
        // to the parser rather than escaped, so a `<script>` in it is a real
        // script element — not the inert `innerHTML`-inserted kind the markdown
        // path produces. `script-src 'nonce-…'` is what makes it inert, and
        // the notebook cannot know this load's nonce.
        //
        // That silently costs the one notebook output form that used to work:
        // a self-contained inline bundle (`plotly.io.write_html(…,
        // include_plotlyjs='inline')` and friends). Rather than leave a blank
        // gap where a chart was, say so.
        if let htmlData = data["text/html"] {
            return "<div class=\"cell-output\">\(htmlData.text)\(blockedScriptNotice(htmlData.text))</div>"
        }
        if let latex = data["text/latex"] {
            return "<div class=\"cell-output\"><div class=\"katex-latex\">\(HTMLEscaper.escape(latex.text))</div></div>"
        }
        if let plain = data["text/plain"] {
            return "<div class=\"cell-output\"><pre>\(HTMLEscaper.escape(plain.text))</pre></div>"
        }
        return ""
    }

    /// A plain, escaped, script-free and style-free notice for a `text/html`
    /// output whose scripts the policy will refuse.
    ///
    /// Emitted Swift-side as static markup reusing the template's existing
    /// `.placeholder-image` class, so it adds no `script-src` or `style-src`
    /// surface of its own. The test is deliberately crude — a literal
    /// `<script` in the output text — because the cost of a false positive is
    /// one extra line of explanation, while the cost of a false negative is
    /// the blank gap this exists to prevent.
    private func blockedScriptNotice(_ html: String) -> String {
        guard html.range(of: "<script", options: .caseInsensitive) != nil else { return "" }
        return "<div class=\"placeholder-image\">This output contains an inline script, "
            + "which this preview does not run.</div>"
    }

    private func renderError(_ message: String, nonce: String) -> String {
        let body = "<div class=\"cell-output cell-error\"><pre>\(HTMLEscaper.escape(message))</pre></div>"
        return HTMLTemplate.wrap(body: body, rendererType: "notebook", nonce: nonce)
    }

}
