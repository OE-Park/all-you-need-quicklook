import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ProjectConfigurationTests: XCTestCase {

    func testQuickLookContentTypesAreNestedUnderExtensionAttributes() throws {
        let propertyList = try extensionInfoPlist()
        let extensionDictionary = try XCTUnwrap(propertyList["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let contentTypes = try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])

        XCTAssertTrue(
            Set(contentTypes).isSuperset(of:
            Set([
                "public.plain-text", "com.apple.log",
                "net.daringfireball.markdown", "org.jupyter.notebook",
                // Data formats conform to public.text, never to
                // public.plain-text, so each has to be named on its own.
                "public.json", "public.yaml", "public.toml",
                "public.source-code", "public.script", "public.xml", "public.html", "public.css",
            ]))
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
        for ext in ["go", "rs", "ps1", "psm1", "psd1", "bash", "zsh", "bat", "cmd", "dart", "cmake", "fsx", "erl", "tf", "zig"] {
            XCTAssertEqual(
                conformanceByExtension[ext], ["public.source-code"],
                ".\(ext) is not imported as source code"
            )
        }
    }

    func testHostAndExtensionDeclareTheSameSourceTypesWithoutClaimingMovies() throws {
        let hostData = try Data(contentsOf: repositoryRoot.appendingPathComponent("AllYouNeedQuickLook/Info.plist"))
        let host = try XCTUnwrap(PropertyListSerialization.propertyList(from: hostData, format: nil) as? [String: Any])
        let hostTypes = try XCTUnwrap(host["UTImportedTypeDeclarations"] as? NSArray)
        let extTypes = try XCTUnwrap(try extensionInfoPlist()["UTImportedTypeDeclarations"] as? NSArray)
        XCTAssertEqual(hostTypes, extTypes)
        let extInfo = try extensionInfoPlist()
        let attrs = (extInfo["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        let supported = attrs?["QLSupportedContentTypes"] as? [String] ?? []
        for declaration in extTypes.compactMap({ $0 as? [String: Any] }) {
            XCTAssertTrue(supported.contains(declaration["UTTypeIdentifier"] as? String ?? ""))
        }
        let imported = extTypes.compactMap { $0 as? [String: Any] }.flatMap {
            (($0["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String]) ?? []
        }
        XCTAssertGreaterThan(imported.count, 200)
        XCTAssertFalse(imported.contains("ts"), "Do not reclassify MPEG transport stream files")
        XCTAssertFalse(imported.contains("wasm"), "Binary WebAssembly is not text")
        XCTAssertEqual(imported.count, Set(imported).count)
    }

    // MARK: - Entitlements

    func testNoTargetUsesAnAppGroup() throws {
        for name in ["AllYouNeedQuickLook/AllYouNeedQuickLook", "QuickLookExtension/QuickLookExtension"] {
            let entitlements = try entitlements(at: name)
            XCTAssertNil(entitlements["com.apple.security.application-groups"], name)
        }
    }

    func testHostMayWriteOnlyItsConfigDirectory() throws {
        let entitlements = try entitlements(at: "AllYouNeedQuickLook/AllYouNeedQuickLook")
        XCTAssertEqual(
            entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-write"] as? [String],
            ["/Library/Application Support/AllYouNeedQuickLook/"]
        )
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
    }

    func testExtensionHasReadOnlyFileAccess() throws {
        let entitlements = try entitlements(at: "QuickLookExtension/QuickLookExtension")
        XCTAssertEqual(
            entitlements["com.apple.security.temporary-exception.files.absolute-path.read-only"] as? [String],
            ["/"]
        )
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
    }

    /// Every slot macOS asks of an app icon is filled, each with a PNG of the
    /// pixel size the slot declares. A missing or mis-sized slot is not a build
    /// error: Finder and the Dock just fall back to a scaled neighbour or the
    /// generic icon, which is easy to miss.
    func testAppIconSetFillsEveryMacSlotAtItsPixelSize() throws {
        let iconSet = repositoryRoot.appendingPathComponent("AllYouNeedQuickLook/Assets.xcassets/AppIcon.appiconset")
        let contents = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))) as? [String: Any]
        )
        let images = try XCTUnwrap(contents["images"] as? [[String: Any]])
        var slots: Set<String> = []
        for image in images {
            let size = try XCTUnwrap(image["size"] as? String)
            let scale = try XCTUnwrap(image["scale"] as? String)
            let filename = try XCTUnwrap(image["filename"] as? String, "\(size)@\(scale) has no file")
            slots.insert("\(size)@\(scale)")

            let points = try XCTUnwrap(Int(size.split(separator: "x")[0]))
            let pixels = points * (scale == "2x" ? 2 : 1)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(iconSet.appendingPathComponent(filename) as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, pixels, filename)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, pixels, filename)
        }
        XCTAssertEqual(slots, Set(["16x16", "32x32", "128x128", "256x256", "512x512"].flatMap { ["\($0)@1x", "\($0)@2x"] }))
    }

    private func entitlements(at name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(name + ".entitlements"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
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
