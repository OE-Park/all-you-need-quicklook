// Tests/ConfigLoaderTests.swift
import XCTest
@testable import Shared

final class ConfigLoaderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadDefaultConfigWhenNoFileExists() {
        let loader = ConfigLoader(containerURL: tempDir)
        let config = loader.load()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.fontFamily, "SF Mono")
        XCTAssertEqual(config.global.fontSize, 13)
    }

    func testSaveAndLoad() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        var config = AppConfig()
        config.global.fontSize = 18
        try loader.save(config)

        let loaded = loader.load()
        XCTAssertEqual(loaded.global.fontSize, 18)
    }

    // MARK: - The bundled default

    /// What "Reset to Default" writes. `AppConfig()` is *not* that default — it
    /// carries no `fileTypes` at all, so saving it would strip the log level
    /// patterns from every `.log` preview, in the QuickLook extension too, and
    /// `load()` would never fall back to the bundled file again because a
    /// `config.json` now exists. The reset must yield the bundled config.
    func testBundledDefaultKeepsTheLogLevelPatterns() throws {
        let patterns = try XCTUnwrap(
            ConfigLoader.bundledDefault().fileTypes?["log"]?.logLevelPatterns,
            "the shipped default lost its log level patterns"
        )
        XCTAssertEqual(Set(patterns.keys), ["error", "warn", "info", "debug"])
        XCTAssertNil(AppConfig().fileTypes,
                     "AppConfig() gained fileTypes; this test no longer proves the two differ")
    }

    /// End to end: resetting, saving and reloading still colours log levels.
    func testResettingToTheBundledDefaultStillColoursLogLevels() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        try loader.save(ConfigLoader.bundledDefault())

        let html = PlainTextRenderer().render(
            content: "ERROR boom\nWARN careful\nINFO fine\nDEBUG noise",
            config: loader.load(),
            fileExtension: "log"
        )
        XCTAssertTrue(html.contains("log-error"))
        XCTAssertTrue(html.contains("log-warn"))
        XCTAssertTrue(html.contains("log-info"))
        XCTAssertTrue(html.contains("log-debug"))
    }

    func testLoadFallsBackOnCorruptFile() throws {
        let corruptPath = tempDir.appendingPathComponent("config.json")
        try "not json".write(to: corruptPath, atomically: true, encoding: .utf8)

        let loader = ConfigLoader(containerURL: tempDir)
        let config = loader.load()
        XCTAssertEqual(config.version, 1)
    }
}
