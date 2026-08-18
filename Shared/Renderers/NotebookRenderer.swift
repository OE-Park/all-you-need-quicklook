// Shared/Renderers/NotebookRenderer.swift
import Foundation

public final class NotebookRenderer: Renderer {

    public init() {}

    public func render(content: String, config: AppConfig, fileExtension: String) -> String {
        guard let data = content.data(using: .utf8),
              let notebook = try? JSONDecoder().decode(Notebook.self, from: data) else {
            return renderError("Error: Failed to parse notebook file.")
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
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            document.querySelectorAll('.markdown-cell-raw').forEach(function(el) {
                var raw = el.innerHTML;
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return hljs.highlightAuto(code).value;
                    },
                    gfm: true
                });
                el.innerHTML = marked.parse(raw);
                el.classList.remove('markdown-cell-raw');
                el.classList.add('markdown-cell');
            });

            document.querySelectorAll('.code-source code').forEach(function(el) {
                hljs.highlightElement(el);
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
                var html = el.innerHTML;
                html = html.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(m, math) {
                    try { return katex.renderToString(math.trim(), { displayMode: true, throwOnError: false }); }
                    catch(e) { return m; }
                });
                html = html.replace(/\\$([^\\$\\n]+?)\\$/g, function(m, math) {
                    try { return katex.renderToString(math.trim(), { displayMode: false, throwOnError: false }); }
                    catch(e) { return m; }
                });
                el.innerHTML = html;
            });
        });
        </script>
        """

        return HTMLTemplate.wrap(body: body, rendererType: "notebook")
    }

    private func renderMarkdownCell(_ cell: Cell) -> String {
        let source = escapeHTML(cell.joinedSource)
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
        let source = escapeHTML(cell.joinedSource)

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
        let source = escapeHTML(cell.joinedSource)
        return """
        <div class="notebook-cell">
            <div class="cell-output"><pre>\(source)</pre></div>
        </div>
        """
    }

    private func renderOutput(_ output: CellOutput) -> String {
        switch output {
        case .stream(let stream):
            let text = escapeHTML(stream.text.joined())
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
            return "<div class=\"cell-output\"><img src=\"data:image/png;base64,\(escapeHTML(png.text))\"></div>"
        }
        if let jpeg = data["image/jpeg"] {
            return "<div class=\"cell-output\"><img src=\"data:image/jpeg;base64,\(escapeHTML(jpeg.text))\"></div>"
        }
        // text/html output from notebooks is trusted content from the notebook
        // author (same trust model as Jupyter itself). CSP blocks external scripts.
        if let htmlData = data["text/html"] {
            return "<div class=\"cell-output\">\(htmlData.text)</div>"
        }
        if let latex = data["text/latex"] {
            return "<div class=\"cell-output\"><div class=\"katex-latex\">\(escapeHTML(latex.text))</div></div>"
        }
        if let plain = data["text/plain"] {
            return "<div class=\"cell-output\"><pre>\(escapeHTML(plain.text))</pre></div>"
        }
        return ""
    }

    private func renderError(_ message: String) -> String {
        let body = "<div class=\"cell-output cell-error\"><pre>\(escapeHTML(message))</pre></div>"
        return HTMLTemplate.wrap(body: body, rendererType: "notebook")
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
