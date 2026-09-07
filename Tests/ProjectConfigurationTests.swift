import Foundation
import XCTest

final class ProjectConfigurationTests: XCTestCase {

    func testQuickLookContentTypesAreNestedUnderExtensionAttributes() throws {
        let infoURL = repositoryRoot
            .appendingPathComponent("QuickLookExtension")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let extensionDictionary = try XCTUnwrap(propertyList["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let contentTypes = try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])

        XCTAssertEqual(
            Set(contentTypes),
            Set(["public.plain-text", "net.daringfireball.markdown", "org.jupyter.notebook"])
        )
        XCTAssertNil(propertyList["QLSupportedContentTypes"])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
