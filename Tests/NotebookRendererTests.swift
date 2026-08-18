// Tests/NotebookRendererTests.swift
import XCTest
@testable import Shared

final class NotebookRendererTests: XCTestCase {

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
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("markdown-cell-raw"))
        XCTAssertTrue(html.contains("# Title"))
    }

    func testCodeCellWithOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["print('hi')"],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["hi\\n"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("cell-source"))
        XCTAssertTrue(html.contains("print("))
        XCTAssertTrue(html.contains("cell-output"))
        XCTAssertTrue(html.contains("hi"))
    }

    func testBase64ImageOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"iVBORw0KGgo=","text/plain":["<Figure>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("data:image/png;base64,iVBORw0KGgo="))
    }

    func testHTMLOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":2,"outputs":[{"output_type":"execute_result","execution_count":2,"metadata":{},"data":{"text/html":["<b>bold</b>"],"text/plain":["bold"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("<b>bold</b>"))
    }

    func testErrorOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"error","ename":"ValueError","evalue":"bad","traceback":["\\u001b[31mValueError\\u001b[0m: bad"]}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("cell-error"))
        XCTAssertTrue(html.contains("ValueError"))
    }

    func testLatexOutput() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"execute_result","execution_count":null,"metadata":{},"data":{"text/latex":["$$E=mc^2$$"],"text/plain":["<IPython.core.display.Latex object>"]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("katex-latex"))
    }

    func testExecutionCountDisplayed() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":["x=1"],"execution_count":42,"outputs":[]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("In [42]"))
    }

    func testBase64ImageEscapesQuotes() {
        let json = makeNotebookJSON(cells: """
        {"cell_type":"code","metadata":{},"source":[""],"execution_count":null,"outputs":[{"output_type":"display_data","metadata":{},"data":{"image/png":"bad\\"><script>alert(1)</script>","text/plain":[""]}}]}
        """)
        let html = renderer.render(content: json, config: config, fileExtension: "ipynb")
        XCTAssertFalse(html.contains("bad\"><script>"))
        XCTAssertTrue(html.contains("&quot;&gt;&lt;script&gt;"))
    }

    func testInvalidJSONFallback() {
        let html = renderer.render(content: "not json at all", config: config, fileExtension: "ipynb")
        XCTAssertTrue(html.contains("notebook"))
        XCTAssertTrue(html.contains("Error")) // shows error message
    }
}
