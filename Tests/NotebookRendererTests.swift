// Tests/NotebookRendererTests.swift
import XCTest
@testable import Shared

final class NotebookRendererTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

    let renderer = NotebookRenderer()
    let config = AppConfig()

    private func makeNotebookJSON(cells: String) -> String {
        """
        {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[\(cells)]}
        """
    }

    func testMarkdownCellRendered() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"markdown","metadata":{},"source":["# Title"]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("markdown-cell-raw"))
        XCTAssertTrue(html.contains("# Title"))
    }

    func testCodeCellWithOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["print('hi')"],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["hi\\n"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("cell-source"))
        XCTAssertTrue(html.contains("print("))
        XCTAssertTrue(html.contains("cell-output"))
        XCTAssertTrue(html.contains("hi"))
    }

    func testBase64ImageOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"iVBORw0KGgo=","text/plain":["<Figure>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("data:image/png;base64,iVBORw0KGgo="))
    }

    func testHTMLOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":2,"outputs":[{"output_type":"execute_result","execution_count":2,"metadata":{},"data":{"text/html":["<b>bold</b>"],"text/plain":["bold"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("<b>bold</b>"))
    }

    /// `script-src` names only this document's nonce, so a self-contained
    /// inline bundle in a `text/html` output (plotly `include_plotlyjs='inline'`
    /// and friends) no longer runs. Leaving a blank gap where the chart was is
    /// the failure mode worth avoiding, so the output carries a notice.
    func testHTMLOutputWithAnInlineScriptCarriesANotice() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":1,"outputs":[{"output_type":"execute_result","execution_count":1,"metadata":{},"data":{"text/html":["<div id=chart></div><script>Plotly.newPlot()<\\/script>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("<div id=chart></div>"), "the output itself was dropped")
        XCTAssertTrue(html.contains("which this preview does not run"))
        XCTAssertTrue(html.contains("placeholder-image"),
                      "the notice must reuse an existing class, not a new style source")
    }

    /// The notice must not appear on the ordinary case — a pandas
    /// `_repr_html_` table is the single most common notebook output.
    func testHTMLOutputWithoutAScriptCarriesNoNotice() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":1,"outputs":[{"output_type":"execute_result","execution_count":1,"metadata":{},"data":{"text/html":["<table class=dataframe><tr><td>1</td></tr></table>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("<table class=dataframe>"), "the output itself was dropped")
        XCTAssertFalse(html.contains("which this preview does not run"))
    }

    func testErrorOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"error","ename":"ValueError","evalue":"bad","traceback":["\\u001b[31mValueError\\u001b[0m: bad"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("cell-error"))
        XCTAssertTrue(html.contains("ValueError"))
    }

    func testLatexOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"execute_result","execution_count":null,"metadata":{},"data":{"text/latex":["$$E=mc^2$$"],"text/plain":["<IPython.core.display.Latex object>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("katex-latex"))
    }

    func testExecutionCountDisplayed() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["x=1"],"execution_count":42,"outputs":[]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("In [42]"))
    }

    func testRawCellRendered() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"raw","metadata":{},"source":["raw text content"]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("raw text content"))
    }

    func testJPEGImageOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/jpeg":"/9j/4AAQSkZJRg==","text/plain":["<Figure>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("data:image/jpeg;base64,/9j/4AAQSkZJRg=="))
    }

    func testCodeCellWithoutExecutionCountShowsEmptyBracket() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["a = 1"],"execution_count":null,"outputs":[]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("In [ ]"))
    }

    func testStreamOutputHTMLEscaped() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["<script>alert(1)</script>"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    }

    func testBase64ImageEscapesQuotes() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"bad\\"><script>alert(1)</script>","text/plain":[""]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertFalse(html.contains("bad\"><script>"))
        XCTAssertTrue(html.contains("&quot;&gt;&lt;script&gt;"))
    }

    func testInvalidJSONFallback() {
        let html = renderer.render(content: "not json at all", config: config, fileExtension: "ipynb", nonce: nonce)
        XCTAssertTrue(html.contains("notebook"))
        XCTAssertTrue(html.contains("Error")) // shows error message
    }
    func testStreamOutputEscapesApostrophe() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["it's unsafe"]}]}
        """)

        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)

        XCTAssertTrue(html.contains("it&#39;s unsafe"))
    }
    func testMarkdownCodeBlocksUseCurrentHighlightJSAPI() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"markdown","metadata":{},"source":["```swift\\nlet x = 1\\n```"]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb", nonce: nonce)

        XCTAssertTrue(html.contains(".markdown-cell pre code"))
        XCTAssertFalse(html.contains("highlight: function"))
    }
}
