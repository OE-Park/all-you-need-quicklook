import Foundation
import UniformTypeIdentifiers
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
            Set([
                "public.plain-text", "com.apple.log",
                "net.daringfireball.markdown", "org.jupyter.notebook",
                // Data formats conform to public.text, never to
                // public.plain-text, so each has to be named on its own.
                "public.json", "public.yaml", "public.toml",
            ])
        )
        XCTAssertNil(propertyList["QLSupportedContentTypes"])
    }

    /// The reason each data format needs its own entry, asserted against the
    /// system's own type tree rather than left as a comment: if a future macOS
    /// made public.json conform to public.plain-text, the extra entries would
    /// be redundant and this would say so.
    func testDataFormatsDoNotReachPlainTextOnTheirOwn() throws {
        let plainText = try XCTUnwrap(UTType("public.plain-text"))
        for identifier in ["public.json", "public.yaml", "public.toml"] {
            let type = try XCTUnwrap(UTType(identifier), "\(identifier) unknown to this system")
            XCTAssertFalse(
                type.conforms(to: plainText),
                "\(identifier) now conforms to public.plain-text; its QLSupportedContentTypes entry is redundant"
            )
            XCTAssertTrue(type.conforms(to: .text), "\(identifier) is not a text type")
        }
    }

    /// Source code already reaches the extension through public.plain-text,
    /// which is why those extensions are deliberately not listed.
    func testSourceCodeAlreadyConformsToPlainText() throws {
        let plainText = try XCTUnwrap(UTType("public.plain-text"))
        for ext in ["swift", "py", "js", "go", "rs", "sh"] {
            let type = try XCTUnwrap(UTType(filenameExtension: ext), ".\(ext) has no type")
            XCTAssertTrue(type.conforms(to: plainText), ".\(ext) needs its own entry after all")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
