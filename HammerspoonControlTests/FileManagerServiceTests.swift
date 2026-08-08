import XCTest
@testable import HammerspoonControl

final class FileManagerServiceTests: XCTestCase {
    var tempDirURL: URL!
    var fileManagerService: FileManagerService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        fileManagerService = FileManagerService(customConfigDirURL: tempDirURL)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirURL.path) {
            try? FileManager.default.removeItem(at: tempDirURL)
        }
        try super.tearDownWithError()
    }

    func testSHA256Computation() {
        let text = "Hello Hammerspoon"
        let hash = fileManagerService.sha256(of: text)
        XCTAssertEqual(hash, "96e708aed0f9e7d1a2b53c5d948587024052cb8a9998a3abab598226ec772ef5")
    }

    func testAtomicWrite() throws {
        let fileURL = tempDirURL.appendingPathComponent("test.txt")
        let content = "Initial Content"

        try fileManagerService.atomicWrite(text: content, to: fileURL)
        XCTAssertTrue(fileManagerService.fileExists(at: fileURL))
        XCTAssertEqual(try fileManagerService.readText(at: fileURL), content)

        let updatedContent = "Updated Content"
        try fileManagerService.atomicWrite(text: updatedContent, to: fileURL)
        XCTAssertEqual(try fileManagerService.readText(at: fileURL), updatedContent)
    }

    func testCollisionSafeBackupCreation() throws {
        let sourceURL = tempDirURL.appendingPathComponent("init.lua")
        try fileManagerService.atomicWrite(text: "baseline content", to: sourceURL)

        let backup1 = try fileManagerService.createCollisionSafeBackup(of: sourceURL, prefix: "init.lua.codex-backup")
        XCTAssertTrue(fileManagerService.fileExists(at: backup1))
        XCTAssertEqual(try fileManagerService.readText(at: backup1), "baseline content")

        let backup2 = try fileManagerService.createCollisionSafeBackup(of: sourceURL, prefix: "init.lua.codex-backup")
        XCTAssertTrue(fileManagerService.fileExists(at: backup2))
        XCTAssertNotEqual(backup1.path, backup2.path)
    }
}
