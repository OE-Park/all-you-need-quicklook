// Tests/ANSIConverterTests.swift
import XCTest
@testable import Shared

final class ANSIConverterTests: XCTestCase {

    func testPlainTextPassesThrough() {
        let result = ANSIConverter.toHTML("Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testRedText() {
        let input = "\u{1B}[31mError occurred\u{1B}[0m"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("color:"))
        XCTAssertTrue(result.contains("Error occurred"))
        XCTAssertFalse(result.contains("\u{1B}"))
    }

    func testBoldText() {
        let input = "\u{1B}[1mBold text\u{1B}[0m"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("font-weight:bold"))
        XCTAssertTrue(result.contains("Bold text"))
    }

    func testNestedStyles() {
        let input = "\u{1B}[1;31mBold red\u{1B}[0m normal"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("Bold red"))
        XCTAssertTrue(result.contains("normal"))
    }

    func testHTMLEntitiesEscaped() {
        let input = "<script>alert('xss')</script>"
        let result = ANSIConverter.toHTML(input)
        XCTAssertFalse(result.contains("<script>"))
        XCTAssertTrue(result.contains("&lt;script&gt;"))
    }

    func testResetThenColorKeepsColor() {
        let input = "\u{1B}[0;31mValueError\u{1B}[0m"
        let result = ANSIConverter.toHTML(input)
        XCTAssertTrue(result.contains("color:"))
        XCTAssertTrue(result.contains("ValueError"))
        XCTAssertFalse(result.contains("\u{1B}"))
    }
}
