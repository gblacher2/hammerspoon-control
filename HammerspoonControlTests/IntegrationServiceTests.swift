import XCTest
@testable import HammerspoonControl

final class MockProcessRunner: ProcessRunnerProtocol {
    var hsExecutablePath: String = "/mock/bin/hs"
    var nightlightExecutablePath: String = "/mock/bin/nightlight"
    var hammerspoonAppPath: String = "/mock/Applications/Hammerspoon.app"

    var reloadCallCount = 0
    var reloadResult = ProcessResult(exitCode: 0, stdout: "reloaded", stderr: "")
    var healthResult = ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: "")
    var sentinelResult: RuntimeSentinelInfo? = RuntimeSentinelInfo(version: 1, isReady: true, generation: "mock_gen_1")

    func runHsReload() throws -> ProcessResult {
        reloadCallCount += 1
        return reloadResult
    }

    func queryRuntimeSentinel() -> (result: ProcessResult, sentinel: RuntimeSentinelInfo?) {
        return (healthResult, sentinelResult)
    }

    func queryRuntimeHealth() -> ProcessResult {
        if !healthResult.isSuccess {
            return healthResult
        }
        guard let s = sentinelResult else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Sentinel missing (_G.hsControlSentinel is nil)")
        }
        guard s.version == 1 else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Unsupported sentinel version \(s.version) (expected 1)")
        }
        guard s.isReady else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Sentinel ready flag is false")
        }
        return ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: "")
    }

    func reloadAndVerifyHealth(previousGeneration: String?, timeoutSeconds: TimeInterval) -> (reloadResult: ProcessResult, healthResult: ProcessResult, freshGeneration: String?) {
        reloadCallCount += 1
        if !reloadResult.isSuccess {
            return (reloadResult, ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Reload command failed: \(reloadResult.stderr)"), nil)
        }
        let health = queryRuntimeHealth()
        if health.isSuccess {
            return (reloadResult, health, "mock_gen_fresh")
        } else {
            return (reloadResult, health, sentinelResult?.generation)
        }
    }

    func checkDependencies() -> [SystemDependency] {
        [
            SystemDependency(id: "hammerspoon", displayName: "Hammerspoon App", expectedPath: hammerspoonAppPath, isPresent: true),
            SystemDependency(id: "hs", displayName: "Hammerspoon CLI (hs)", expectedPath: hsExecutablePath, isPresent: true),
            SystemDependency(id: "nightlight", displayName: "nightlight CLI", expectedPath: nightlightExecutablePath, isPresent: true)
        ]
    }
}

final class FailingFileManagerService: FileManagerServiceProtocol {
    private let base: FileManagerServiceProtocol
    var failWriteTargetURLPath: String?

    init(base: FileManagerServiceProtocol, failWriteTargetURLPath: String? = nil) {
        self.base = base
        self.failWriteTargetURLPath = failWriteTargetURLPath
    }

    var configDirURL: URL { base.configDirURL }
    var initLuaURL: URL { base.initLuaURL }
    var hammerspoonControlDirURL: URL { base.hammerspoonControlDirURL }
    var settingsJsonURL: URL { base.settingsJsonURL }
    var runtimeLuaURL: URL { base.runtimeLuaURL }
    var installJsonURL: URL { base.installJsonURL }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func readText(at url: URL) throws -> String { try base.readText(at: url) }
    func sha256(of text: String) -> String { base.sha256(of: text) }
    func sha256(of url: URL) throws -> String { try base.sha256(of: url) }
    func sha256(of data: Data) -> String { base.sha256(of: data) }

    private func shouldFail(_ url: URL) -> Bool {
        guard let failPath = failWriteTargetURLPath else { return false }
        return url.standardizedFileURL.path == URL(fileURLWithPath: failPath).standardizedFileURL.path
    }

    func atomicWrite(data: Data, to url: URL) throws {
        if shouldFail(url) {
            throw NSError(domain: "FailingFileManagerService", code: 99, userInfo: [NSLocalizedDescriptionKey: "Simulated write failure for \(url.path)"])
        }
        try base.atomicWrite(data: data, to: url)
    }

    func atomicWrite(text: String, to url: URL) throws {
        if shouldFail(url) {
            throw NSError(domain: "FailingFileManagerService", code: 99, userInfo: [NSLocalizedDescriptionKey: "Simulated write failure for \(url.path)"])
        }
        try base.atomicWrite(text: text, to: url)
    }

    func ensureDirectoryExists(at url: URL) throws {
        try base.ensureDirectoryExists(at: url)
    }

    func createCollisionSafeBackup(of url: URL, prefix: String) throws -> URL {
        try base.createCollisionSafeBackup(of: url, prefix: prefix)
    }
}

final class IntegrationServiceTests: XCTestCase {
    var tempConfigDir: URL!
    var fileManagerService: FileManagerService!
    var mockRunner: MockProcessRunner!
    var integrationService: IntegrationService!

    let baselineContent = "-- baseline config\nprint('hello')"
    var baselineSha: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempConfigDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempConfigDir, withIntermediateDirectories: true)

        fileManagerService = FileManagerService(customConfigDirURL: tempConfigDir)
        mockRunner = MockProcessRunner()

        baselineSha = fileManagerService.sha256(of: baselineContent)
        integrationService = IntegrationService(
            fileManagerService: fileManagerService,
            processRunner: mockRunner,
            expectedBaselineSha256: baselineSha
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempConfigDir.path) {
            try? FileManager.default.removeItem(at: tempConfigDir)
        }
        try super.tearDownWithError()
    }

    func testDetectStateReadyToInstall() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        let state = integrationService.detectState()
        if case .readyToInstall(_, let hash) = state {
            XCTAssertEqual(hash, baselineSha)
        } else {
            XCTFail("Expected readyToInstall state, got \(state)")
        }
    }

    func testDetectStateRefusesUnrecognizedConfig() throws {
        let initURL = fileManagerService.initLuaURL
        let customContent = "-- customized config\nsome_random_lua_code()"
        try fileManagerService.atomicWrite(text: customContent, to: initURL)

        let state = integrationService.detectState()
        if case .unsafeUnrecognizedConfig(let reason) = state {
            XCTAssertTrue(reason.contains("does not match the expected unmanaged baseline"))
        } else {
            XCTFail("Expected unsafeUnrecognizedConfig state, got \(state)")
        }
    }

    func testDetectStateInstalledRuntimeInactiveWhenSentinelQueryFails() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        mockRunner.healthResult = ProcessResult(exitCode: 1, stdout: "", stderr: "IPC connection refused")
        mockRunner.sentinelResult = nil

        let state = integrationService.detectState()
        if case .installedRuntimeInactive(_, let reason) = state {
            XCTAssertTrue(reason.contains("IPC connection refused"))
        } else {
            XCTFail("Expected installedRuntimeInactive state when health query fails, got \(state)")
        }
    }

    func testInstallIntegrationCreatesBackupAndManagedBootstrap() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        let result = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        let manifest = result.manifest

        XCTAssertEqual(manifest.originalInitSha256, baselineSha)
        XCTAssertTrue(fileManagerService.fileExists(at: URL(fileURLWithPath: manifest.originalInitBackupPath)))

        let newInitText = try fileManagerService.readText(at: initURL)
        XCTAssertTrue(newInitText.contains("-- BEGIN Hammerspoon Control"))
        XCTAssertTrue(newInitText.contains("hs.configdir"))
        XCTAssertFalse(newInitText.contains("hs.configDir"))

        XCTAssertTrue(fileManagerService.fileExists(at: fileManagerService.settingsJsonURL))
        XCTAssertTrue(fileManagerService.fileExists(at: fileManagerService.runtimeLuaURL))
        XCTAssertTrue(fileManagerService.fileExists(at: fileManagerService.installJsonURL))

        let state = integrationService.detectState()
        if case .installed = state {
            // Success
        } else {
            XCTFail("Expected installed state after installation, got \(state)")
        }
    }

    func testFailureInjectionAtWriteStagesLeavesInitLuaRecoverableAndStateNotInstalled() throws {
        let initURL = fileManagerService.initLuaURL

        // Test Stage 3 failure (settings.json write error)
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        let failingFM3 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.settingsJsonURL.path)
        let service3 = IntegrationService(fileManagerService: failingFM3, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service3.installIntegration(expectedInitSha256: baselineSha))
        XCTAssertEqual(try fileManagerService.readText(at: initURL), baselineContent)
        if case .installed = service3.detectState() {
            XCTFail("State detection must not return .installed after stage 3 failure")
        }

        // Test Stage 4 failure (runtime.lua write error)
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        let failingFM4 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.runtimeLuaURL.path)
        let service4 = IntegrationService(fileManagerService: failingFM4, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service4.installIntegration(expectedInitSha256: baselineSha))
        XCTAssertEqual(try fileManagerService.readText(at: initURL), baselineContent)
        if case .installed = service4.detectState() {
            XCTFail("State detection must not return .installed after stage 4 failure")
        }

        // Test Stage 5 failure (install.json write error)
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        let failingFM5 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.installJsonURL.path)
        let service5 = IntegrationService(fileManagerService: failingFM5, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service5.installIntegration(expectedInitSha256: baselineSha))
        XCTAssertEqual(try fileManagerService.readText(at: initURL), baselineContent)
        if case .installed = service5.detectState() {
            XCTFail("State detection must not return .installed after stage 5 failure")
        }

        // Test Stage 6 failure (init.lua write error)
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        let failingFM6 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.initLuaURL.path)
        let service6 = IntegrationService(fileManagerService: failingFM6, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service6.installIntegration(expectedInitSha256: baselineSha))
        XCTAssertEqual(try fileManagerService.readText(at: initURL), baselineContent)
        if case .installed = service6.detectState() {
            XCTFail("State detection must not return .installed after stage 6 failure")
        }
    }

    func testFailureInjectionAtUpdateStagesPreservesPreviousValidState() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        let initialResult = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        let originalManifest = initialResult.manifest

        let previousRuntimeData = Data("-- previous valid managed runtime\nreturn true\n".utf8)
        try fileManagerService.atomicWrite(data: previousRuntimeData, to: fileManagerService.runtimeLuaURL)

        var previousManifest = originalManifest
        previousManifest.runtimeSha256 = fileManagerService.sha256(of: previousRuntimeData)
        let previousInstallJsonData = try JSONEncoder().encode(previousManifest)
        try fileManagerService.atomicWrite(data: previousInstallJsonData, to: fileManagerService.installJsonURL)

        let previousInitData = try fileManagerService.readData(at: initURL)

        func assertPreviousValidStatePreserved(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(try fileManagerService.readData(at: initURL), previousInitData, file: file, line: line)
            XCTAssertEqual(try fileManagerService.readData(at: fileManagerService.runtimeLuaURL), previousRuntimeData, file: file, line: line)
            XCTAssertEqual(try fileManagerService.readData(at: fileManagerService.installJsonURL), previousInstallJsonData, file: file, line: line)

            let preservedManifest = try JSONDecoder().decode(
                InstallManifest.self,
                from: fileManagerService.readData(at: fileManagerService.installJsonURL)
            )
            XCTAssertEqual(preservedManifest.originalInitSha256, originalManifest.originalInitSha256, file: file, line: line)
            XCTAssertEqual(preservedManifest.originalInitBackupPath, originalManifest.originalInitBackupPath, file: file, line: line)
        }

        // Stage 1: runtime.lua replacement fails before any managed file changes.
        let failingFM1 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.runtimeLuaURL.path)
        let service1 = IntegrationService(fileManagerService: failingFM1, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service1.updateManagedRuntime())
        try assertPreviousValidStatePreserved()

        // Stage 2: runtime.lua replacement succeeds, install.json fails, and runtime.lua rolls back byte-exactly.
        let failingFM2 = FailingFileManagerService(base: fileManagerService, failWriteTargetURLPath: fileManagerService.installJsonURL.path)
        let service2 = IntegrationService(fileManagerService: failingFM2, processRunner: mockRunner, expectedBaselineSha256: baselineSha)

        XCTAssertThrowsError(try service2.updateManagedRuntime())
        try assertPreviousValidStatePreserved()

        // A changed init.lua is never overwritten as part of a runtime update.
        let changedInitData = Data((IntegrationService.managedBootstrapText + "\n-- user change that must be preserved\n").utf8)
        try fileManagerService.atomicWrite(data: changedInitData, to: initURL)

        XCTAssertThrowsError(try integrationService.updateManagedRuntime()) { error in
            XCTAssertTrue(error.localizedDescription.contains("matches no bootstrap this app has written"))
        }
        XCTAssertEqual(try fileManagerService.readData(at: initURL), changedInitData)
        XCTAssertEqual(try fileManagerService.readData(at: fileManagerService.runtimeLuaURL), previousRuntimeData)
        XCTAssertEqual(try fileManagerService.readData(at: fileManagerService.installJsonURL), previousInstallJsonData)
    }

    func testInactiveToHealthyTransition() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        // Initially inactive
        mockRunner.healthResult = ProcessResult(exitCode: 1, stdout: "", stderr: "Sentinel ready flag is false")
        mockRunner.sentinelResult = RuntimeSentinelInfo(version: 1, isReady: false, generation: "gen_0")

        let state1 = integrationService.detectState()
        if case .installedRuntimeInactive(_, let reason) = state1 {
            XCTAssertTrue(reason.contains("ready flag is false"))
        } else {
            XCTFail("Expected installedRuntimeInactive state, got \(state1)")
        }

        // Trigger retry after runtime becomes healthy
        mockRunner.healthResult = ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: "")
        mockRunner.sentinelResult = RuntimeSentinelInfo(version: 1, isReady: true, generation: "gen_1")

        let retryRes = integrationService.retryReloadAndVerifyHealth()
        XCTAssertTrue(retryRes.reloadResult.isSuccess)
        XCTAssertTrue(retryRes.healthResult.isSuccess)

        let state2 = integrationService.detectState()
        if case .installed = state2 {
            // Transitioned to healthy!
        } else {
            XCTFail("Expected installed state after successful retry, got \(state2)")
        }
    }

    func testInactiveToFailedTransition() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        mockRunner.healthResult = ProcessResult(exitCode: 1, stdout: "", stderr: "Sentinel missing")
        mockRunner.sentinelResult = nil

        let retryRes = integrationService.retryReloadAndVerifyHealth()
        XCTAssertTrue(retryRes.reloadResult.isSuccess)
        XCTAssertFalse(retryRes.healthResult.isSuccess)
        XCTAssertTrue(retryRes.healthResult.stderr.contains("Sentinel missing"))

        let state = integrationService.detectState()
        if case .installedRuntimeInactive(_, let reason) = state {
            XCTAssertTrue(reason.contains("Sentinel missing"))
        } else {
            XCTFail("Expected installedRuntimeInactive state after failed retry, got \(state)")
        }
    }

    func testInstallRefusesIfFileChangesRightBeforeInstallAndLeavesInitUntouched() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        // Mutate file right before install
        let mutatedContent = baselineContent + "\n-- mutated!"
        try fileManagerService.atomicWrite(text: mutatedContent, to: initURL)

        XCTAssertThrowsError(try integrationService.installIntegration(expectedInitSha256: baselineSha))

        // Verify init.lua was left untouched as mutatedContent
        let currentContent = try fileManagerService.readText(at: initURL)
        XCTAssertEqual(currentContent, mutatedContent)
    }

    func testDedicatedUpdateManagedRuntimePreservesRestorationChain() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        let initialResult = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        let initialManifest = initialResult.manifest

        // Modify runtime file to simulate outdated runtime
        try fileManagerService.atomicWrite(text: "-- outdated runtime content", to: fileManagerService.runtimeLuaURL)

        let stateAfterMod = integrationService.detectState()
        if case .outdatedRuntime(let manifest) = stateAfterMod {
            XCTAssertEqual(manifest.originalInitSha256, baselineSha)
            XCTAssertEqual(manifest.originalInitBackupPath, initialManifest.originalInitBackupPath)
        } else {
            XCTFail("Expected outdatedRuntime state, got \(stateAfterMod)")
        }

        let updateResult = try integrationService.updateManagedRuntime()
        let updatedManifest = updateResult.manifest

        XCTAssertEqual(updatedManifest.originalInitSha256, baselineSha)
        XCTAssertEqual(updatedManifest.originalInitBackupPath, initialManifest.originalInitBackupPath)
        XCTAssertNotEqual(updatedManifest.runtimeSha256, fileManagerService.sha256(of: "-- outdated runtime content"))

        let restoredState = integrationService.detectState()
        if case .installed = restoredState {
            // Success
        } else {
            XCTFail("Expected installed state after update, got \(restoredState)")
        }
    }

    func testRestorePreAppConfigRestoresOriginalBytes() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)

        let result = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        let manifest = result.manifest
        XCTAssertTrue(try fileManagerService.readText(at: initURL).contains("-- BEGIN Hammerspoon Control"))

        let restoreResult = try integrationService.restorePreAppConfig()

        XCTAssertEqual(restoreResult.restoredBackupPath, manifest.originalInitBackupPath)
        XCTAssertTrue(fileManagerService.fileExists(at: URL(fileURLWithPath: restoreResult.safetyBackupPath)))

        let restoredInitText = try fileManagerService.readText(at: initURL)
        XCTAssertEqual(restoredInitText, baselineContent)
    }

    // MARK: - Bootstrap recognition
    //
    // A build shipped an init.lua whose IPC block referenced `hs.ipc.create`, which does not
    // exist on Hammerspoon 1.1.1. Updates then compared the live file byte-for-byte against
    // the newer constant, never matched, and refused forever. These cover the recovery path.

    func testUpdateAcceptsLegacyBootstrapAndUpgradesItInPlace() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        try fileManagerService.atomicWrite(text: IntegrationService.legacyIPCCreateBootstrapText, to: initURL)

        let result = try integrationService.updateManagedRuntime()

        XCTAssertTrue(result.reloadResult.isSuccess)
        XCTAssertEqual(try fileManagerService.readText(at: initURL), IntegrationService.managedBootstrapText)
    }

    func testUpdateBacksUpInitBeforeUpgradingBootstrap() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        try fileManagerService.atomicWrite(text: IntegrationService.legacyIPCCreateBootstrapText, to: initURL)

        _ = try integrationService.updateManagedRuntime()

        let siblings = try FileManager.default.contentsOfDirectory(atPath: initURL.deletingLastPathComponent().path)
        let backups = siblings.filter { $0.hasPrefix("init.lua.pre-bootstrap-upgrade-backup") }
        XCTAssertEqual(backups.count, 1)

        let backupURL = initURL.deletingLastPathComponent().appendingPathComponent(backups[0])
        XCTAssertEqual(try fileManagerService.readText(at: backupURL), IntegrationService.legacyIPCCreateBootstrapText)
    }

    func testDetectStateReportsOutdatedBootstrapForLegacyInit() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)
        try fileManagerService.atomicWrite(text: IntegrationService.legacyIPCCreateBootstrapText, to: initURL)

        guard case .outdatedBootstrap = integrationService.detectState() else {
            return XCTFail("Expected .outdatedBootstrap, got \(integrationService.detectState())")
        }
    }

    func testDetectStateRefusesMarkerBearingInitThatMatchesNoKnownBootstrap() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        let handEdited = IntegrationService.managedBootstrapText + "\n-- hand-edited by the user\n"
        try fileManagerService.atomicWrite(text: handEdited, to: initURL)

        guard case .unsafeUnrecognizedConfig = integrationService.detectState() else {
            return XCTFail("Expected .unsafeUnrecognizedConfig, got \(integrationService.detectState())")
        }
    }

    func testTrailingWhitespaceDoesNotLockOutUpdates() {
        XCTAssertTrue(IntegrationService.matchesRecognizedBootstrap(IntegrationService.managedBootstrapText + "\n\n"))
        XCTAssertTrue(IntegrationService.isCurrentBootstrap(IntegrationService.managedBootstrapText + "\n"))
    }

    func testCurrentBootstrapUsesRequireForIPC() {
        // `hs.ipc.create` is nil on Hammerspoon 1.1.1; `require` is what actually starts the
        // IPC server the app depends on for every sentinel query.
        XCTAssertTrue(IntegrationService.managedBootstrapText.contains("require(\"hs.ipc\")"))
        XCTAssertFalse(IntegrationService.managedBootstrapText.contains("hs.ipc.create"))
    }

    func testDetectStateResyncsStaleManifestRuntimeHash() throws {
        let initURL = fileManagerService.initLuaURL
        try fileManagerService.atomicWrite(text: baselineContent, to: initURL)
        _ = try integrationService.installIntegration(expectedInitSha256: baselineSha)

        let manifestURL = fileManagerService.installJsonURL
        var manifest = try JSONDecoder().decode(InstallManifest.self, from: try fileManagerService.readData(at: manifestURL))
        let trueSha = manifest.runtimeSha256
        manifest.runtimeSha256 = "stale0000000000000000000000000000000000000000000000000000000000"
        try fileManagerService.atomicWrite(data: try JSONEncoder().encode(manifest), to: manifestURL)

        _ = integrationService.detectState()

        let resynced = try JSONDecoder().decode(InstallManifest.self, from: try fileManagerService.readData(at: manifestURL))
        XCTAssertEqual(resynced.runtimeSha256, trueSha)
    }
}
