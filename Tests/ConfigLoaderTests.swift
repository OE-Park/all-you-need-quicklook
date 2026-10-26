// Tests/ConfigLoaderTests.swift
import XCTest
@testable import Shared

final class ConfigLoaderTests: XCTestCase {

    private let nonce = PreviewWebView.makeNonce()

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

    func testSuccessfulSaveNotifiesAfterNewConfigurationIsReadable() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        let saved = expectation(forNotification: Notification.Name("QuickLookConfigurationDidSave"), object: nil) { _ in
            loader.load().global.fontSize == 21
        }
        var config = AppConfig()
        config.global.fontSize = 21
        try loader.save(config)
        wait(for: [saved], timeout: 0.3)
    }

    func testFailedSaveDoesNotPublishAConfigurationChange() {
        // A regular file where the directory should be: creating it must fail.
        let blocker = tempDir.appendingPathComponent("blocker")
        try? Data().write(to: blocker)
        let loader = ConfigLoader(containerURL: blocker.appendingPathComponent("AllYouNeedQuickLook"))
        let saved = expectation(forNotification: Notification.Name("QuickLookConfigurationDidSave"), object: nil)
        saved.isInverted = true
        XCTAssertThrowsError(try loader.save(AppConfig()))
        wait(for: [saved], timeout: 0.1)
    }

    // MARK: - Location and failure reporting

    func testDefaultDirectoryIsRealHomeApplicationSupport() {
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        XCTAssertEqual(ConfigLoader.defaultDirectory.path,
                       home + "/Library/Application Support/AllYouNeedQuickLook")
    }

    func testSaveCreatesMissingDirectory() throws {
        let dir = tempDir.appendingPathComponent("nested/AllYouNeedQuickLook")
        try ConfigLoader(containerURL: dir).save(AppConfig())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path))
    }

    func testMissingFileIsDefaultAndNotUnreadable() {
        let r = ConfigLoader(containerURL: tempDir).loadResult()
        XCTAssertFalse(r.isUnreadable)
    }

    func testCorruptFileIsDefaultAndUnreadable() throws {
        try Data("{".utf8).write(to: tempDir.appendingPathComponent("config.json"))
        let r = ConfigLoader(containerURL: tempDir).loadResult()
        XCTAssertTrue(r.isUnreadable)
        XCTAssertEqual(r.config, ConfigLoader.bundledDefault())
    }

    func testAddPersistsOnlyExtensionAndRetainsOtherDraftEdits() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        let saved = ConfigLoader.bundledDefault()
        try loader.save(saved)
        var draft = saved
        draft.global.fontSize = 29
        draft.global.allowExternalImages = true
        draft.fileTypes?["log"]?.showLineNumbers = false
        let result = try loader.saveAddedFileType(" .YAML ", draft: draft)
        let disk = loader.load()
        XCTAssertEqual(disk.global, saved.global)
        XCTAssertEqual(disk.fileTypes?["log"], saved.fileTypes?["log"])
        XCTAssertNotNil(disk.fileTypes?["yaml"])
        XCTAssertEqual(result.global, draft.global)
        XCTAssertEqual(result.fileTypes?["log"], draft.fileTypes?["log"])
        XCTAssertNotNil(result.fileTypes?["yaml"])
    }

    func testInaccessibleDirectoryIsUnreadableInsteadOfMissing() throws {
        if geteuid() == 0 { throw XCTSkip("root bypasses directory permissions") }
        let denied = tempDir.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: denied.appendingPathComponent("config.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
        XCTAssertTrue(ConfigLoader(containerURL: denied).loadResult().isUnreadable)
    }

    func testExplicitImportAndInvalidImportPreserveSavedSettings() throws {
        let loader = ConfigLoader(containerURL: tempDir)
        let source = tempDir.appendingPathComponent("legacy.json")
        var legacy = AppConfig()
        legacy.global.fontSize = 23
        try JSONEncoder().encode(legacy).write(to: source)
        try loader.importConfiguration(from: source)
        XCTAssertEqual(loader.load(), legacy)
        try Data("{".utf8).write(to: source)
        XCTAssertThrowsError(try loader.importConfiguration(from: source))
        XCTAssertEqual(loader.load(), legacy)
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
            fileExtension: "log", nonce: nonce
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
