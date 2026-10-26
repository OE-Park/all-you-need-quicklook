import XCTest
@testable import Shared

final class FileTypeSupportTests: XCTestCase {
    private let support = FileTypeSupport(supportedTypeIdentifiers: [
        "public.plain-text", "public.yaml", "public.json", "public.toml", "org.jupyter.notebook"
    ])

    func testNormalizationAndInvalidInput() {
        XCTAssertEqual(FileTypeSupport.normalizedExtension(" .YaML \n"), "yaml")
        for invalid in ["", ".", "../yaml", "a b", "a/b", "..yaml", "a.yaml"] {
            XCTAssertNil(FileTypeSupport.normalizedExtension(invalid), invalid)
        }
    }

    func testYAMLAndJSONAreExplicitlySupported() {
        XCTAssertEqual(support.status(for: "yaml"), .eligible)
        XCTAssertEqual(support.status(for: "json"), .eligible)
        XCTAssertEqual(support.status(for: "swift"), .eligible)
    }

    func testUnsupportedAndUnknownTypesAreNotClaimed() {
        XCTAssertEqual(support.status(for: "xml"), .unsupported)
        XCTAssertEqual(support.status(for: "aynqlunknown9823"), .unknown)
        XCTAssertEqual(FileTypeSupport(supportedTypeIdentifiers: []).status(for: "yaml"), .unsupported)
    }

    func testAddingNormalizesAndPreservesExistingSettings() throws {
        let old = FileTypeConfig(fontSize: 22, syntaxHighlight: false)
        let config = AppConfig(fileTypes: ["yaml": old])
        let duplicate = try support.adding(" .YAML ", to: config)
        XCTAssertEqual(duplicate.fileTypes?["yaml"], old)
        let added = try support.adding("json", to: config)
        XCTAssertNotNil(added.fileTypes?["json"])
        XCTAssertEqual(added.fileTypes?["yaml"], old)
        XCTAssertThrowsError(try support.adding("../bad", to: config))
    }
}
