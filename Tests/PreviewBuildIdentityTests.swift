import XCTest
@testable import Shared

final class PreviewBuildIdentityTests: XCTestCase {
    func testProductionDocumentIsUnchanged() {
        let html = "<body class=\"markdown\"><p>Hello</p></body>"
        XCTAssertEqual(PreviewBuildIdentity.annotate(html, identifier: "com.yohanpark.AllYouNeedQuickLook.QuickLookExtension"), html)
    }
    func testRandomizedTestPreviewIdentifiesItsBuild() {
        let result = PreviewBuildIdentity.annotate("<body class=\"markdown\"><p>Hello</p></body>", identifier: "com.yohanpark.AllYouNeedQuickLook.test.1234abcd.QuickLookExtension")
        XCTAssertTrue(result.contains("Test build 1234abcd"))
        XCTAssertTrue(result.contains("<p>Hello</p>"))
        XCTAssertFalse(result.contains("</body><div"))
    }
}
