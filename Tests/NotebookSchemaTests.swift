// Tests/NotebookSchemaTests.swift
import XCTest
@testable import Shared

final class NotebookSchemaTests: XCTestCase {

    func testDecodeMinimalNotebook() throws {
        let json = """
        {
            "nbformat": 4,
            "nbformat_minor": 5,
            "metadata": {},
            "cells": [
                {
                    "cell_type": "markdown",
                    "metadata": {},
                    "source": ["# Title\\n", "Some text"]
                },
                {
                    "cell_type": "code",
                    "metadata": {},
                    "source": ["print('hello')"],
                    "execution_count": 1,
                    "outputs": [
                        {
                            "output_type": "stream",
                            "name": "stdout",
                            "text": ["hello\\n"]
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        XCTAssertEqual(notebook.cells.count, 2)
        XCTAssertEqual(notebook.cells[0].cellType, .markdown)
        XCTAssertEqual(notebook.cells[0].joinedSource, "# Title\nSome text")
        XCTAssertEqual(notebook.cells[1].cellType, .code)
        XCTAssertEqual(notebook.cells[1].executionCount, 1)
        XCTAssertEqual(notebook.cells[1].outputs?.count, 1)
    }

    func testDecodeOutputTypes() throws {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{
                "cell_type": "code", "metadata": {}, "source": [""],
                "execution_count": null,
                "outputs": [
                    { "output_type": "stream", "name": "stdout", "text": ["out\\n"] },
                    { "output_type": "display_data", "metadata": {},
                      "data": { "image/png": "iVBOR...", "text/plain": ["<Figure>"] } },
                    { "output_type": "execute_result", "execution_count": 2, "metadata": {},
                      "data": { "text/html": ["<b>bold</b>"], "text/plain": ["bold"] } },
                    { "output_type": "error", "ename": "ValueError", "evalue": "bad",
                      "traceback": ["\\u001b[31mValueError\\u001b[0m: bad"] }
                ]
            }]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        let outputs = notebook.cells[0].outputs!
        XCTAssertEqual(outputs.count, 4)

        switch outputs[0] {
        case .stream(let s): XCTAssertEqual(s.text.joined(), "out\n")
        default: XCTFail("Expected stream")
        }

        switch outputs[1] {
        case .displayData(let d): XCTAssertNotNil(d.data["image/png"])
        default: XCTFail("Expected display_data")
        }

        switch outputs[2] {
        case .executeResult(let r): XCTAssertEqual(r.executionCount, 2)
        default: XCTFail("Expected execute_result")
        }

        switch outputs[3] {
        case .error(let e):
            XCTAssertEqual(e.ename, "ValueError")
            XCTAssertEqual(e.traceback.count, 1)
        default: XCTFail("Expected error")
        }
    }

    func testDecodeSourceAsSingleString() throws {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{
                "cell_type": "markdown",
                "metadata": {},
                "source": "# Title\\nSome text"
            }]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        XCTAssertEqual(notebook.cells[0].joinedSource, "# Title\nSome text")
    }

    func testDecodeStreamTextAsSingleString() throws {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{
                "cell_type": "code",
                "metadata": {},
                "source": ["print('hi')"],
                "execution_count": 1,
                "outputs": [
                    { "output_type": "stream", "name": "stdout", "text": "hello\\n" }
                ]
            }]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        XCTAssertEqual(notebook.cells[0].joinedSource, "print('hi')")
        switch notebook.cells[0].outputs![0] {
        case .stream(let s): XCTAssertEqual(s.text.joined(), "hello\n")
        default: XCTFail("Expected stream")
        }
    }

    func testDecodeStringSourceAndStreamTextTogether() throws {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{
                "cell_type": "code",
                "metadata": {},
                "source": "print('hi')",
                "execution_count": 1,
                "outputs": [
                    { "output_type": "stream", "name": "stdout", "text": "hello\\n" }
                ]
            }]
        }
        """.data(using: .utf8)!

        let notebook = try JSONDecoder().decode(Notebook.self, from: json)
        XCTAssertEqual(notebook.cells[0].joinedSource, "print('hi')")
        switch notebook.cells[0].outputs![0] {
        case .stream(let s): XCTAssertEqual(s.text.joined(), "hello\n")
        default: XCTFail("Expected stream")
        }
    }

    func testMissingSourceIsKeyNotFound() {
        let json = """
        {
            "nbformat": 4, "nbformat_minor": 5, "metadata": {},
            "cells": [{ "cell_type": "markdown", "metadata": {} }]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Notebook.self, from: json)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("expected keyNotFound, got \(error)")
            }
            XCTAssertEqual(key.stringValue, "source")
        }
    }
}
