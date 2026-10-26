import Foundation
import UniformTypeIdentifiers
import XCTest

final class ProjectConfigurationTests: XCTestCase {

    func testQuickLookContentTypesAreNestedUnderExtensionAttributes() throws {
        let propertyList = try extensionInfoPlist()
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

    /// Source code the system itself types reaches the extension through
    /// public.source-code -> public.plain-text, which is why those extensions
    /// are deliberately not listed.
    func testSystemSourceCodeAlreadyConformsToPlainText() throws {
        let plainText = try XCTUnwrap(UTType("public.plain-text"))
        for ext in ["swift", "py", "js", "sh"] {
            let type = try XCTUnwrap(UTType(filenameExtension: ext), ".\(ext) has no type")
            XCTAssertTrue(type.conforms(to: plainText), ".\(ext) needs its own entry after all")
        }
    }

    /// macOS does not type .go or .rs. They only resolve to source code where
    /// some other app (an editor) imports them; on a clean Mac -- the CI
    /// runner is one -- they are dynamic types and quicklookd never asks this
    /// extension. Asserting the system type tree here would only test which
    /// apps the machine has, so this asserts the extension's own import.
    func testExtensionImportsSourceTypesTheSystemDoesNotDeclare() throws {
        let declarations = try XCTUnwrap(
            try extensionInfoPlist()["UTImportedTypeDeclarations"] as? [[String: Any]]
        )
        var conformanceByExtension: [String: [String]] = [:]
        for declaration in declarations {
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            for ext in tags?["public.filename-extension"] as? [String] ?? [] {
                conformanceByExtension[ext] = declaration["UTTypeConformsTo"] as? [String]
            }
        }
        for ext in ["go", "rs"] {
            XCTAssertEqual(
                conformanceByExtension[ext], ["public.source-code"],
                ".\(ext) is not imported as source code"
            )
        }
    }

    private func extensionInfoPlist() throws -> [String: Any] {
        let infoURL = repositoryRoot
            .appendingPathComponent("QuickLookExtension")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
