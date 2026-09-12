import XCTest
@testable import Shared

@MainActor
final class PreviewControllerLifecycleTests: XCTestCase {
    func testReusedControllerReplacesTransportWhenSavedImageSettingsChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("example.md")
        try "# Example".write(to: file, atomically: true, encoding: .utf8)
        let loader = ConfigLoader(containerURL: directory)
        var config = AppConfig()
        config.global.allowExternalImages = true
        config.global.imageTimeoutSeconds = 1
        try loader.save(config)
        let controller = PreviewViewController(nibName: nil, bundle: nil)
        controller.configLoader = loader
        let root = controller.view
        try await controller.preparePreviewOfFile(at: file)
        let first = try XCTUnwrap((controller.view as? PreviewWebView) ?? controller.view.subviews.compactMap { $0 as? PreviewWebView }.first)
        config.global.allowExternalImages = false
        config.global.imageTimeoutSeconds = 7
        try loader.save(config)
        try await controller.preparePreviewOfFile(at: file)
        let second = try XCTUnwrap((controller.view as? PreviewWebView) ?? controller.view.subviews.compactMap { $0 as? PreviewWebView }.first)
        XCTAssertTrue(root === controller.view, "QuickLook retains the root view; replace its child, not the root")
        XCTAssertFalse(first === second, "Old native transport must not survive a document/configuration change")
        XCTAssertNotEqual(first.installedNonce, second.installedNonce)
    }
}
