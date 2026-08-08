import SwiftUI

public struct FirstRunInstallerView: View {
    let state: IntegrationState
    let dependencies: [SystemDependency]
    let errorMessage: String?
    let restoreMessage: String?
    let isBusy: Bool
    let onInstall: () -> Void

    public init(
        state: IntegrationState,
        dependencies: [SystemDependency],
        errorMessage: String? = nil,
        restoreMessage: String? = nil,
        isBusy: Bool = false,
        onInstall: @escaping () -> Void
    ) {
        self.state = state
        self.dependencies = dependencies
        self.errorMessage = errorMessage
        self.restoreMessage = restoreMessage
        self.isBusy = isBusy
        self.onInstall = onInstall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()

            Divider()

            DependenciesView(dependencies: dependencies)

            Divider()

            IntegrationStatusDetailView(state: state)

            OutcomeMessagesView(errorMessage: errorMessage, restoreMessage: restoreMessage)

            Spacer()

            FooterNoticeView()

            InstallButtonView(state: state, isBusy: isBusy, onInstall: onInstall)
        }
        .padding(16)
        .frame(width: 460, height: 440)
    }
}

/// Without this the installer silently discarded every error it was handed: a refused
/// update looked identical to a button that did nothing at all.
private struct OutcomeMessagesView: View {
    let errorMessage: String?
    let restoreMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let restoreMessage = restoreMessage, !restoreMessage.isEmpty {
                Label(restoreMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                    .padding(6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hammerspoon Control")
                    .font(.system(size: 16, weight: .bold))
                Text("Native menu-bar controller for display warmth & Cmd+scroll zoom")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct DependenciesView: View {
    let dependencies: [SystemDependency]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System Dependencies")
                .font(.system(size: 12, weight: .semibold))

            ForEach(dependencies) { dep in
                HStack(spacing: 8) {
                    Image(systemName: dep.isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(dep.isPresent ? .green : .red)
                        .font(.system(size: 12))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(dep.displayName)
                            .font(.system(size: 11, weight: .medium))
                        Text(dep.expectedPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(dep.isPresent ? "Found" : "Missing")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(dep.isPresent ? .green : .red)
                }
            }
        }
    }
}

private struct IntegrationStatusDetailView: View {
    let state: IntegrationState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Integration Baseline Analysis")
                .font(.system(size: 12, weight: .semibold))

            switch state {
            case .readyToInstall(let backupPath, let hash):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Live init.lua matches known baseline fingerprint.", systemImage: "shield.checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.green)

                    Text("SHA-256: \(hash)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("Planned collision-safe backup destination:")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.top, 2)

                    Text(backupPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            case .installed(let manifest):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Integration is active.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)

                    Text("Original baseline backup: \(manifest.originalInitBackupPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            case .installedRuntimeInactive(let manifest, let reason):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Files installed, but Lua runtime is inactive.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)

                    Text("Reason: \(reason)")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)

                    Text("Original baseline backup: \(manifest.originalInitBackupPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            case .outdatedRuntime(let manifest):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Managed runtime update required.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)

                    Text("Installed backup: \(manifest.originalInitBackupPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            case .outdatedBootstrap(let manifest):
                VStack(alignment: .leading, spacing: 4) {
                    Label("init.lua uses an older recognized bootstrap.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)

                    Text("Updating rewrites the managed section of init.lua to the current bootstrap. A timestamped backup is taken first.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text("Installed backup: \(manifest.originalInitBackupPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            case .missingDependencies(let deps):
                let names = deps.map { $0.displayName }.joined(separator: ", ")
                Label("Missing dependencies (\(names)). Install dependencies before continuing.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            case .unsafeUnrecognizedConfig(let reason):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Automatic migration refused.", systemImage: "hand.raised.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)

                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

private struct FooterNoticeView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
                .font(.system(size: 12))
            Text("No files under ~/.hammerspoon change until you click Install integration.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

private struct InstallButtonView: View {
    let state: IntegrationState
    let isBusy: Bool
    let onInstall: () -> Void

    var body: some View {
        Button(action: onInstall) {
            HStack {
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                }
                Text(isBusy ? "Working…" : buttonTitle)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isInstallable || isBusy)
    }

    // `.installedRuntimeInactive` is deliberately absent: that state routes to SettingsView,
    // which owns the retry flow. Listing it here produced a button with no handler behind it.
    private var isInstallable: Bool {
        switch state {
        case .readyToInstall, .outdatedRuntime, .outdatedBootstrap: return true
        default: return false
        }
    }

    private var buttonTitle: String {
        switch state {
        case .readyToInstall: return "Install integration"
        case .outdatedRuntime: return "Update managed integration"
        case .outdatedBootstrap: return "Update managed bootstrap"
        case .installedRuntimeInactive: return "Retry reload & activate runtime"
        case .installed: return "Integration Installed"
        case .missingDependencies: return "Missing Dependencies"
        case .unsafeUnrecognizedConfig: return "Migration Refused"
        }
    }
}
