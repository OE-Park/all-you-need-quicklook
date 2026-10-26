import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Shared

final class LocalImageSchemeHandlerTests: XCTestCase {
    private var root: URL!
    private var docs: URL!

    override func setUpWithError() throws {
        // Resolved up front: /var/folders is a symlink to /private/var/folders.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs.appendingPathComponent("img"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testResolvesSiblingSubdirAndParent() throws {
        try writePNG(docs.appendingPathComponent("a.png"))
        try writePNG(docs.appendingPathComponent("img/a.png"))
        try writePNG(root.appendingPathComponent("up.png"))

        XCTAssertEqual(try LocalImageSchemeHandler.resolve(ref: "a.png", in: docs), docs.appendingPathComponent("a.png"))
        XCTAssertEqual(try LocalImageSchemeHandler.resolve(ref: "img/a.png", in: docs), docs.appendingPathComponent("img/a.png"))
        XCTAssertEqual(try LocalImageSchemeHandler.resolve(ref: "../up.png", in: docs), root.appendingPathComponent("up.png"))
    }

    func testDecodesOnceAndIgnoresQueryAndFragment() throws {
        try writePNG(docs.appendingPathComponent("a b.png"))
        try writePNG(docs.appendingPathComponent("a.png"))
        let spaced = docs.appendingPathComponent("a b.png")

        XCTAssertEqual(try LocalImageSchemeHandler.resolve(ref: "a%20b.png", in: docs), spaced)
        XCTAssertEqual(try LocalImageSchemeHandler.resolve(ref: "a b.png", in: docs), spaced)
        XCTAssertEqual(
            try LocalImageSchemeHandler.resolve(ref: "a.png?v=2#x", in: docs),
            docs.appendingPathComponent("a.png")
        )
        // Decoded once, not twice: "%2520" is the literal text "%20", not a space.
        XCTAssertThrowsError(try LocalImageSchemeHandler.resolve(ref: "a%2520b.png", in: docs)) {
            XCTAssertEqual($0 as? LocalImageError, .notFound)
        }
    }

    func testRefusesAbsoluteAndSchemes() {
        for ref in ["/etc/hosts", "file:///x.png", "http://x/y.png", "%2Fetc%2Fhosts", "data:image/png;base64,AA=="] {
            XCTAssertThrowsError(try LocalImageSchemeHandler.resolve(ref: ref, in: docs), ref) {
                XCTAssertEqual($0 as? LocalImageError, .notRelative, ref)
            }
        }
    }

    func testMissingFileIsNotFound() {
        XCTAssertThrowsError(try LocalImageSchemeHandler.resolve(ref: "nope.png", in: docs)) {
            XCTAssertEqual($0 as? LocalImageError, .notFound)
        }
    }

    func testServesPNGWithMimeType() throws {
        let url = docs.appendingPathComponent("a.png")
        try writePNG(url)
        let image = try LocalImageSchemeHandler.validatedImage(at: url)
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertFalse(image.data.isEmpty)
    }

    func testServesSVGWithSVGRoot() throws {
        let url = docs.appendingPathComponent("a.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8).write(to: url)
        XCTAssertEqual(try LocalImageSchemeHandler.validatedImage(at: url).mimeType, "image/svg+xml")
    }

    func testRefusesSVGWithoutSVGRoot() throws {
        let url = docs.appendingPathComponent("a.svg")
        try Data("<html><body>x</body></html>".utf8).write(to: url)
        assertThrows(.notAnImage) { _ = try LocalImageSchemeHandler.validatedImage(at: url) }
    }

    func testRefusesImageExtensionWithNonImageBytes() throws {
        let url = docs.appendingPathComponent("x.png")
        try Data("hello".utf8).write(to: url)
        assertThrows(.notAnImage) { _ = try LocalImageSchemeHandler.validatedImage(at: url) }
    }

    func testRefusesNonImageExtension() throws {
        let url = docs.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: url)
        assertThrows(.notAnImage) { _ = try LocalImageSchemeHandler.validatedImage(at: url) }
    }

    func testRefusesOver25MB() throws {
        let url = docs.appendingPathComponent("big.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(LocalImageSchemeHandler.maxBytes + 1))
        try handle.close()
        assertThrows(.tooLarge) { _ = try LocalImageSchemeHandler.validatedImage(at: url) }
    }

    func testRefusesDirectoryNamedLikeAnImage() throws {
        let url = docs.appendingPathComponent("dir.png")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        assertThrows(.notRegularFile) { _ = try LocalImageSchemeHandler.validatedImage(at: url) }
    }

    func testSymlinks() throws {
        try writePNG(root.appendingPathComponent("outside.png"))
        try Data("hello".utf8).write(to: docs.appendingPathComponent("target.txt"))
        let fm = FileManager.default
        try fm.createSymbolicLink(at: docs.appendingPathComponent("linkdir.png"), withDestinationURL: docs.appendingPathComponent("img"))
        try fm.createSymbolicLink(at: docs.appendingPathComponent("linktxt.png"), withDestinationURL: docs.appendingPathComponent("target.txt"))
        try fm.createSymbolicLink(at: docs.appendingPathComponent("linkout.png"), withDestinationURL: root.appendingPathComponent("outside.png"))

        for (ref, expected) in [("linkdir.png", LocalImageError.notRegularFile), ("linktxt.png", .notAnImage)] {
            let resolved = try LocalImageSchemeHandler.resolve(ref: ref, in: docs)
            assertThrows(expected, ref) { _ = try LocalImageSchemeHandler.validatedImage(at: resolved) }
        }
        let served = try LocalImageSchemeHandler.validatedImage(
            at: try LocalImageSchemeHandler.resolve(ref: "linkout.png", in: docs)
        )
        XCTAssertEqual(served.mimeType, "image/png")
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: LocalImageError, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), message, file: file, line: line) {
            XCTAssertEqual($0 as? LocalImageError, expected, message, file: file, line: line)
        }
    }

    private func writePNG(_ url: URL) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
