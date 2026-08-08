import Foundation

public protocol IntegrationServiceProtocol {
    func detectState() -> IntegrationState
    func installIntegration(expectedInitSha256: String) throws -> (manifest: InstallManifest, reloadResult: ProcessResult, healthResult: ProcessResult)
    func updateManagedRuntime() throws -> (manifest: InstallManifest, reloadResult: ProcessResult, healthResult: ProcessResult)
    func applySettings(_ settings: Settings) throws -> (reloadResult: ProcessResult, healthResult: ProcessResult)
    func retryReloadAndVerifyHealth() -> (reloadResult: ProcessResult, healthResult: ProcessResult)
    func restorePreAppConfig() throws -> (restoredBackupPath: String, safetyBackupPath: String, reloadResult: ProcessResult)
    func loadCurrentSettings() -> Settings
}

public final class IntegrationService: IntegrationServiceProtocol {
    private let fileManagerService: FileManagerServiceProtocol
    private let processRunner: ProcessRunnerProtocol
    private let expectedBaselineSha256: String

    public static let knownBaselineSha256 = "b90f23843142261c456194152e8edd82455c8d5c76208824ee0c17ad80610324"

    public init(
        fileManagerService: FileManagerServiceProtocol = FileManagerService(),
        processRunner: ProcessRunnerProtocol = ProcessRunner(),
        expectedBaselineSha256: String = IntegrationService.knownBaselineSha256
    ) {
        self.fileManagerService = fileManagerService
        self.processRunner = processRunner
        self.expectedBaselineSha256 = expectedBaselineSha256
    }

    public static var managedBootstrapText: String {
        """
        -- BEGIN Hammerspoon Control
        -- Managed by Hammerspoon Control. Do not edit this section directly.
        require("hs.ipc")

        local managedRuntime = hs.configdir .. "/hammerspoon-control/runtime.lua"
        if hs.fs.attributes(managedRuntime) then
          local ok, err = pcall(dofile, managedRuntime)
          if not ok then
            hs.showError("Hammerspoon Control runtime error: " .. tostring(err))
          end
        else
          print("Hammerspoon Control: managed runtime.lua not found at " .. managedRuntime)
        end
        -- END Hammerspoon Control
        """
    }

    /// Bootstrap texts this app is willing to take ownership of and rewrite in place.
    ///
    /// The first entry is always the current text. Later entries are historical forms
    /// shipped by earlier builds: an init.lua matching one of them was written by this
    /// app, not hand-edited by the user, so upgrading it in place is safe. Anything
    /// matching none of these is treated as a user modification and left alone.
    public static var recognizedBootstrapTexts: [String] {
        [managedBootstrapText, legacyIPCCreateBootstrapText]
    }

    /// Shipped before 2026-08. `hs.ipc.create` does not exist on Hammerspoon 1.1.1, so the
    /// guarded block never ran and IPC started only as a side effect of the `hs.ipc`
    /// reference triggering Hammerspoon's lazy module autoloader.
    static var legacyIPCCreateBootstrapText: String {
        """
        -- BEGIN Hammerspoon Control
        -- Managed by Hammerspoon Control. Do not edit this section directly.
        if hs.ipc and hs.ipc.create then
          hs.ipc.create()
        end

        local managedRuntime = hs.configdir .. "/hammerspoon-control/runtime.lua"
        if hs.fs.attributes(managedRuntime) then
          local ok, err = pcall(dofile, managedRuntime)
          if not ok then
            hs.showError("Hammerspoon Control runtime error: " .. tostring(err))
          end
        else
          print("Hammerspoon Control: managed runtime.lua not found at " .. managedRuntime)
        end
        -- END Hammerspoon Control
        """
    }

    /// Compares ignoring trailing whitespace, so a stray newline appended by an editor
    /// does not lock the user out of updates.
    static func matchesRecognizedBootstrap(_ text: String) -> Bool {
        recognizedBootstrapText(matching: text) != nil
    }

    static func recognizedBootstrapText(matching text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return recognizedBootstrapTexts.first {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
    }

    static func isCurrentBootstrap(_ text: String) -> Bool {
        recognizedBootstrapText(matching: text) == managedBootstrapText
    }

    public func detectState() -> IntegrationState {
        let state = computeState()
        AppLog.integration.debug("detectState -> \(state.statusDescription, privacy: .public)")
        return state
    }

    private func computeState() -> IntegrationState {
        let deps = processRunner.checkDependencies()
        let missing = deps.filter { !$0.isPresent }
        if !missing.isEmpty {
            return .missingDependencies(missing)
        }

        let initURL = fileManagerService.initLuaURL
        guard fileManagerService.fileExists(at: initURL) else {
            return .unsafeUnrecognizedConfig(reason: "init.lua does not exist at \(initURL.path)")
        }

        do {
            let initText = try fileManagerService.readText(at: initURL)
            let currentSha = fileManagerService.sha256(of: initText)

            if initText.contains("-- BEGIN Hammerspoon Control") {
                let installJsonURL = fileManagerService.installJsonURL
                let runtimeURL = fileManagerService.runtimeLuaURL
                guard fileManagerService.fileExists(at: installJsonURL) && fileManagerService.fileExists(at: runtimeURL) else {
                    return .unsafeUnrecognizedConfig(reason: "Managed markers present in init.lua but installation manifest/runtime file is missing.")
                }

                let installData = try fileManagerService.readData(at: installJsonURL)
                let manifest = try JSONDecoder().decode(InstallManifest.self, from: installData)

                guard IntegrationService.matchesRecognizedBootstrap(initText) else {
                    return .unsafeUnrecognizedConfig(reason: "init.lua carries the managed markers but its contents match no bootstrap this app has ever written. It was edited outside the app, so automatic updates are refused. Restore the recognized bootstrap or the pre-app configuration to continue.")
                }

                if let bundledRuntimeData = loadBundledRuntimeData() {
                    let bundledSha = fileManagerService.sha256(of: bundledRuntimeData)
                    let currentRuntimeSha = try fileManagerService.sha256(of: runtimeURL)
                    if bundledSha != currentRuntimeSha {
                        return .outdatedRuntime(manifest: manifest)
                    }
                    resyncManifestRuntimeShaIfNeeded(manifest: manifest, actualRuntimeSha: currentRuntimeSha)
                }

                if !IntegrationService.isCurrentBootstrap(initText) {
                    return .outdatedBootstrap(manifest: manifest)
                }

                let healthResult = processRunner.queryRuntimeHealth()
                if healthResult.isSuccess && healthResult.stdout.contains("HEALTHY_V1") {
                    return .installed(manifest: manifest)
                } else {
                    let reason = healthResult.stderr.isEmpty ? (healthResult.stdout.isEmpty ? "Runtime sentinel not ready or IPC disconnected." : healthResult.stdout) : healthResult.stderr
                    return .installedRuntimeInactive(manifest: manifest, reason: reason)
                }
            } else {
                if currentSha == expectedBaselineSha256 {
                    let parentDir = initURL.deletingLastPathComponent().path
                    let predictedBackupPath = "\(parentDir)/init.lua.codex-backup-YYYYMMDD-HHMMSS"
                    return .readyToInstall(backupPathToCreate: predictedBackupPath, initSha256: currentSha)
                } else {
                    return .unsafeUnrecognizedConfig(reason: "Existing init.lua does not match the expected unmanaged baseline (current SHA: \(currentSha.prefix(8))... vs expected SHA: \(expectedBaselineSha256.prefix(8))...).")
                }
            }
        } catch {
            return .unsafeUnrecognizedConfig(reason: "Could not read init.lua: \(error.localizedDescription)")
        }
    }

    public func installIntegration(expectedInitSha256: String) throws -> (manifest: InstallManifest, reloadResult: ProcessResult, healthResult: ProcessResult) {
        let initURL = fileManagerService.initLuaURL
        guard fileManagerService.fileExists(at: initURL) else {
            throw NSError(domain: "IntegrationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot install: init.lua missing at \(initURL.path)"])
        }

        let liveText = try fileManagerService.readText(at: initURL)
        let liveSha = fileManagerService.sha256(of: liveText)

        guard liveSha == expectedInitSha256 else {
            throw NSError(domain: "IntegrationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Installation aborted: init.lua fingerprint changed right before installation! Expected \(expectedInitSha256.prefix(8))..., found \(liveSha.prefix(8))..."])
        }

        let preGen = processRunner.queryRuntimeSentinel().sentinel?.generation

        let backupURL = try fileManagerService.createCollisionSafeBackup(of: initURL, prefix: "init.lua.codex-backup")

        try fileManagerService.ensureDirectoryExists(at: fileManagerService.hammerspoonControlDirURL)

        if !fileManagerService.fileExists(at: fileManagerService.settingsJsonURL) {
            let defaultSettingsData = try JSONEncoder().encode(Settings.default)
            try fileManagerService.atomicWrite(data: defaultSettingsData, to: fileManagerService.settingsJsonURL)
        }

        let runtimeData: Data
        if let bundled = loadBundledRuntimeData() {
            runtimeData = bundled
        } else {
            throw NSError(domain: "IntegrationService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bundled runtime.lua resource not found in app bundle"])
        }
        try fileManagerService.atomicWrite(data: runtimeData, to: fileManagerService.runtimeLuaURL)
        let runtimeSha = fileManagerService.sha256(of: runtimeData)

        let manifest = InstallManifest(
            version: 1,
            installedAt: Date(),
            originalInitSha256: liveSha,
            originalInitBackupPath: backupURL.path,
            runtimeSha256: runtimeSha
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try fileManagerService.atomicWrite(data: manifestData, to: fileManagerService.installJsonURL)

        try fileManagerService.atomicWrite(text: IntegrationService.managedBootstrapText, to: initURL)

        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)

        return (manifest: manifest, reloadResult: reloadResult, healthResult: healthResult)
    }

    public func updateManagedRuntime() throws -> (manifest: InstallManifest, reloadResult: ProcessResult, healthResult: ProcessResult) {
        let manifestURL = fileManagerService.installJsonURL
        guard fileManagerService.fileExists(at: manifestURL) else {
            throw NSError(domain: "IntegrationService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot update runtime: install.json manifest missing at \(manifestURL.path)"])
        }

        let manifestData = try fileManagerService.readData(at: manifestURL)
        var manifest = try JSONDecoder().decode(InstallManifest.self, from: manifestData)

        let initURL = fileManagerService.initLuaURL
        guard fileManagerService.fileExists(at: initURL) else {
            throw NSError(domain: "IntegrationService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Cannot update runtime: init.lua is missing at \(initURL.path)"])
        }

        let currentInitText = try fileManagerService.readText(at: initURL)
        guard IntegrationService.matchesRecognizedBootstrap(currentInitText) else {
            throw NSError(
                domain: "IntegrationService",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Runtime update refused: init.lua matches no bootstrap this app has written, so it was edited outside the app. Restore the recognized managed bootstrap or restore the pre-app configuration before retrying."]
            )
        }
        let bootstrapNeedsUpgrade = !IntegrationService.isCurrentBootstrap(currentInitText)

        let runtimeURL = fileManagerService.runtimeLuaURL
        guard fileManagerService.fileExists(at: runtimeURL) else {
            throw NSError(domain: "IntegrationService", code: 14, userInfo: [NSLocalizedDescriptionKey: "Cannot update runtime: existing runtime.lua is missing at \(runtimeURL.path)"])
        }
        let previousRuntimeData = try fileManagerService.readData(at: runtimeURL)

        guard let runtimeData = loadBundledRuntimeData() else {
            throw NSError(domain: "IntegrationService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Bundled runtime.lua resource not found in app bundle"])
        }

        let preGen = processRunner.queryRuntimeSentinel().sentinel?.generation

        var runtimeWasReplaced = false
        var initWasRewritten = false
        do {
            if bootstrapNeedsUpgrade {
                _ = try fileManagerService.createCollisionSafeBackup(of: initURL, prefix: "init.lua.pre-bootstrap-upgrade-backup")
                try fileManagerService.atomicWrite(text: IntegrationService.managedBootstrapText, to: initURL)
                initWasRewritten = true
            }

            try fileManagerService.atomicWrite(data: runtimeData, to: runtimeURL)
            runtimeWasReplaced = true

            manifest.runtimeSha256 = fileManagerService.sha256(of: runtimeData)
            let updatedManifestData = try JSONEncoder().encode(manifest)
            try fileManagerService.atomicWrite(data: updatedManifestData, to: manifestURL)
        } catch {
            var rollbackFailures: [String] = []
            if runtimeWasReplaced {
                do {
                    try fileManagerService.atomicWrite(data: previousRuntimeData, to: runtimeURL)
                } catch let rollbackError {
                    rollbackFailures.append("runtime.lua: \(rollbackError.localizedDescription)")
                }
            }
            if initWasRewritten {
                do {
                    try fileManagerService.atomicWrite(text: currentInitText, to: initURL)
                } catch let rollbackError {
                    rollbackFailures.append("init.lua: \(rollbackError.localizedDescription)")
                }
            }
            if !rollbackFailures.isEmpty {
                throw NSError(
                    domain: "IntegrationService",
                    code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "Runtime update failed and rollback could not restore every file. Update error: \(error.localizedDescription). Rollback errors — \(rollbackFailures.joined(separator: "; "))"]
                )
            }
            throw error
        }

        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
        return (manifest: manifest, reloadResult: reloadResult, healthResult: healthResult)
    }

    public func applySettings(_ settings: Settings) throws -> (reloadResult: ProcessResult, healthResult: ProcessResult) {
        try settings.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)

        let preGen = processRunner.queryRuntimeSentinel().sentinel?.generation

        try fileManagerService.atomicWrite(data: data, to: fileManagerService.settingsJsonURL)

        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
        return (reloadResult: reloadResult, healthResult: healthResult)
    }

    public func retryReloadAndVerifyHealth() -> (reloadResult: ProcessResult, healthResult: ProcessResult) {
        let preGen = processRunner.queryRuntimeSentinel().sentinel?.generation
        let (reloadResult, healthResult, _) = processRunner.reloadAndVerifyHealth(previousGeneration: preGen, timeoutSeconds: 12.0)
        return (reloadResult: reloadResult, healthResult: healthResult)
    }

    public func restorePreAppConfig() throws -> (restoredBackupPath: String, safetyBackupPath: String, reloadResult: ProcessResult) {
        let manifestURL = fileManagerService.installJsonURL
        guard fileManagerService.fileExists(at: manifestURL) else {
            throw NSError(domain: "IntegrationService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot restore: install.json manifest missing at \(manifestURL.path)"])
        }

        let manifestData = try fileManagerService.readData(at: manifestURL)
        let manifest = try JSONDecoder().decode(InstallManifest.self, from: manifestData)

        let backupURL = URL(fileURLWithPath: manifest.originalInitBackupPath)
        guard fileManagerService.fileExists(at: backupURL) else {
            throw NSError(domain: "IntegrationService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Original backup file missing at \(backupURL.path)"])
        }

        let backupData = try fileManagerService.readData(at: backupURL)
        let backupSha = fileManagerService.sha256(of: backupData)
        guard backupSha == manifest.originalInitSha256 else {
            throw NSError(domain: "IntegrationService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Original backup file integrity check failed! Expected \(manifest.originalInitSha256.prefix(8))..., found \(backupSha.prefix(8))..."])
        }

        let initURL = fileManagerService.initLuaURL
        var safetyBackupPath = ""
        if fileManagerService.fileExists(at: initURL) {
            let safetyURL = try fileManagerService.createCollisionSafeBackup(of: initURL, prefix: "init.lua.pre-restore-backup")
            safetyBackupPath = safetyURL.path
        }

        try fileManagerService.atomicWrite(data: backupData, to: initURL)

        let reloadResult = (try? processRunner.runHsReload()) ?? ProcessResult(exitCode: 1, stdout: "", stderr: "Could not trigger reload")

        return (restoredBackupPath: backupURL.path, safetyBackupPath: safetyBackupPath, reloadResult: reloadResult)
    }

    public func loadCurrentSettings() -> Settings {
        let settingsURL = fileManagerService.settingsJsonURL
        guard fileManagerService.fileExists(at: settingsURL),
              let data = try? fileManagerService.readData(at: settingsURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return settings
    }

    private func loadBundledRuntimeData() -> Data? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_RUNTIME_PATH"], !override.isEmpty {
            return try? Data(contentsOf: URL(fileURLWithPath: override))
        }
        #endif
        guard let url = Bundle.main.url(forResource: "runtime", withExtension: "lua") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// `install.json` records the runtime hash at install time. If the file on disk was
    /// replaced out-of-band the manifest goes stale while still matching the bundle, which
    /// makes the installed state hard to read during debugging. Quietly bring it back in
    /// line; a failure here is cosmetic and must never block state detection.
    private func resyncManifestRuntimeShaIfNeeded(manifest: InstallManifest, actualRuntimeSha: String) {
        guard manifest.runtimeSha256 != actualRuntimeSha else { return }
        var updated = manifest
        updated.runtimeSha256 = actualRuntimeSha
        guard let data = try? JSONEncoder().encode(updated) else { return }
        try? fileManagerService.atomicWrite(data: data, to: fileManagerService.installJsonURL)
    }
}
