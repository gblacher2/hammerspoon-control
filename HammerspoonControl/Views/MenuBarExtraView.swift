import SwiftUI

@MainActor
public struct MenuBarExtraView: View {
    @State private var state: IntegrationState = .unsafeUnrecognizedConfig(reason: "Initializing...")
    @State private var dependencies: [SystemDependency] = []
    @State private var draftSettings: Settings = .default
    @State private var savedSettings: Settings = .default
    @State private var lastAppliedAt: Date? = nil
    @State private var lastReloadResult: ProcessResult? = nil
    @State private var errorMessage: String? = nil
    @State private var restoreMessage: String? = nil
    @State private var isBusy: Bool = false

    @ObservedObject var statusMonitor: StatusMonitor

    private let integrationService: IntegrationServiceProtocol
    private let processRunner: ProcessRunnerProtocol

    public init(
        statusMonitor: StatusMonitor? = nil,
        integrationService: IntegrationServiceProtocol = IntegrationService(),
        processRunner: ProcessRunnerProtocol = ProcessRunner()
    ) {
        self.statusMonitor = statusMonitor ?? StatusMonitor()
        self.integrationService = integrationService
        self.processRunner = processRunner
    }

    public var body: some View {
        Group {
            switch state {
            case .readyToInstall, .outdatedRuntime, .outdatedBootstrap, .missingDependencies, .unsafeUnrecognizedConfig:
                FirstRunInstallerView(
                    state: state,
                    dependencies: dependencies,
                    errorMessage: errorMessage,
                    restoreMessage: restoreMessage,
                    isBusy: isBusy,
                    onInstall: handleInstall
                )
            case .installed, .installedRuntimeInactive:
                SettingsView(
                    draftSettings: $draftSettings,
                    savedSettings: savedSettings,
                    statusMonitor: statusMonitor,
                    state: state,
                    lastAppliedAt: lastAppliedAt,
                    lastReloadResult: lastReloadResult,
                    errorMessage: errorMessage,
                    restoreMessage: restoreMessage,
                    onPauseWarmth: handlePauseWarmth,
                    onResumeWarmth: handleResumeWarmth,
                    onApply: handleApply,
                    onRevert: handleRevert,
                    onRestoreDefaults: handleRestoreDefaults,
                    onRestorePreApp: handleRestorePreApp,
                    onRetryReload: handleRetryReload,
                    onQuit: handleQuit
                )
            }
        }
        .task { await refreshState() }
    }

    /// Every service call below shells out to `hs` and can block for seconds. Running them
    /// inline on the main actor froze the whole popover with no visible sign of progress,
    /// which is indistinguishable from a button that does nothing.
    private func inBackground<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withBusyState(_ work: @escaping () async -> Void) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            await work()
            isBusy = false
        }
    }

    private func refreshState() async {
        let service = integrationService
        let runner = processRunner

        let refreshed = try? await inBackground {
            (deps: runner.checkDependencies(), state: service.detectState())
        }
        guard let refreshed = refreshed else { return }

        self.dependencies = refreshed.deps
        self.state = refreshed.state

        switch refreshed.state {
        case .installed, .installedRuntimeInactive:
            if let loaded = try? await inBackground({ service.loadCurrentSettings() }) {
                self.savedSettings = loaded
                self.draftSettings = loaded
            }
        default:
            break
        }
    }

    private func handleInstall() {
        withBusyState {
            errorMessage = nil
            restoreMessage = nil

            let service = integrationService
            let currentState = state
            do {
                if case .readyToInstall(_, let hash) = currentState {
                    let res = try await inBackground { try service.installIntegration(expectedInitSha256: hash) }
                    self.lastReloadResult = res.reloadResult
                    if !res.reloadResult.isSuccess {
                        self.errorMessage = "Files installed, but reload command failed: \(res.reloadResult.stderr)"
                    } else if !res.healthResult.isSuccess {
                        self.errorMessage = "Files installed, but runtime health check failed: \(res.healthResult.stderr)"
                    } else {
                        self.restoreMessage = "Integration installed and runtime sentinel verified healthy."
                    }
                } else if case .outdatedRuntime = currentState {
                    try await performManagedUpdate(service: service)
                } else if case .outdatedBootstrap = currentState {
                    try await performManagedUpdate(service: service)
                }
                await refreshState()
            } catch {
                errorMessage = "Installation/Update failed: \(error.localizedDescription)"
                await refreshState()
            }
        }
    }

    private func performManagedUpdate(service: IntegrationServiceProtocol) async throws {
        let res = try await inBackground { try service.updateManagedRuntime() }
        self.lastReloadResult = res.reloadResult
        if !res.reloadResult.isSuccess {
            self.errorMessage = "Managed files updated, but reload command failed: \(res.reloadResult.stderr)"
        } else if !res.healthResult.isSuccess {
            self.errorMessage = "Managed files updated, but runtime health check failed: \(res.healthResult.stderr)"
        } else {
            self.restoreMessage = "Managed integration updated and runtime sentinel verified healthy."
        }
    }

    private func handleApply() {
        withBusyState {
            errorMessage = nil
            restoreMessage = nil

            let service = integrationService
            let settings = draftSettings
            do {
                let (reloadRes, healthRes) = try await inBackground { try service.applySettings(settings) }
                self.lastReloadResult = reloadRes
                if reloadRes.isSuccess && healthRes.isSuccess {
                    self.savedSettings = settings
                    self.lastAppliedAt = Date()
                } else if !reloadRes.isSuccess {
                    self.errorMessage = "Hammerspoon reload command failed: \(reloadRes.stderr)"
                } else {
                    self.errorMessage = "Hammerspoon reload succeeded, but runtime health check failed: \(healthRes.stderr)"
                }
                await refreshState()
            } catch {
                errorMessage = "Apply failed: \(error.localizedDescription)"
                await refreshState()
            }
        }
    }

    private func handleRetryReload() {
        withBusyState {
            errorMessage = nil
            restoreMessage = nil

            let service = integrationService
            guard let (reloadRes, healthRes) = try? await inBackground({ service.retryReloadAndVerifyHealth() }) else {
                errorMessage = "Reload could not be started."
                return
            }

            self.lastReloadResult = reloadRes
            if !reloadRes.isSuccess {
                self.errorMessage = "Reload command failed: \(reloadRes.stderr)"
            } else if !healthRes.isSuccess {
                self.errorMessage = "Reload succeeded, but runtime health check failed: \(healthRes.stderr)"
            } else {
                self.restoreMessage = "Hammerspoon reloaded and runtime sentinel verified healthy."
            }
            await refreshState()
        }
    }

    private func handleRevert() {
        draftSettings = savedSettings
        errorMessage = nil
    }

    private func handleRestoreDefaults() {
        draftSettings = .default
    }

    private func handleRestorePreApp() {
        withBusyState {
            errorMessage = nil
            restoreMessage = nil

            let service = integrationService
            do {
                let res = try await inBackground { try service.restorePreAppConfig() }
                self.lastReloadResult = res.reloadResult
                self.restoreMessage = "Restored pre-app config. Active init.lua restored from \(res.restoredBackupPath). Safety backup saved to \(res.safetyBackupPath)."
                await refreshState()
            } catch {
                errorMessage = "Restoration failed: \(error.localizedDescription)"
                await refreshState()
            }
        }
    }

    private func handlePauseWarmth(minutes: Int) {
        draftSettings.warmth.pauseUntilEpoch = Date().timeIntervalSince1970 + Double(minutes * 60)
        handleApply()
        statusMonitor.refreshStatus()
    }

    private func handleResumeWarmth() {
        draftSettings.warmth.pauseUntilEpoch = nil
        handleApply()
        statusMonitor.refreshStatus()
    }

    private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
