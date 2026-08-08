import SwiftUI

@MainActor
public struct SettingsView: View {
    @Binding var draftSettings: Settings
    let savedSettings: Settings
    let state: IntegrationState
    let lastAppliedAt: Date?
    let lastReloadResult: ProcessResult?
    let errorMessage: String?
    let restoreMessage: String?

    @ObservedObject var statusMonitor: StatusMonitor
    let onPauseWarmth: (Int) -> Void
    let onResumeWarmth: () -> Void

    let onApply: () -> Void
    let onRevert: () -> Void
    let onRestoreDefaults: () -> Void
    let onRestorePreApp: () -> Void
    let onRetryReload: () -> Void
    let onQuit: () -> Void

    @State private var showAdvancedWarmth = false
    @State private var newBuiltInName = ""
    @State private var showRestoreConfirmation = false

    public init(
        draftSettings: Binding<Settings>,
        savedSettings: Settings,
        statusMonitor: StatusMonitor,
        state: IntegrationState,
        lastAppliedAt: Date?,
        lastReloadResult: ProcessResult?,
        errorMessage: String?,
        restoreMessage: String?,
        onPauseWarmth: @escaping (Int) -> Void,
        onResumeWarmth: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onRevert: @escaping () -> Void,
        onRestoreDefaults: @escaping () -> Void,
        onRestorePreApp: @escaping () -> Void,
        onRetryReload: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self._draftSettings = draftSettings
        self.savedSettings = savedSettings
        self.statusMonitor = statusMonitor
        self.state = state
        self.lastAppliedAt = lastAppliedAt
        self.lastReloadResult = lastReloadResult
        self.errorMessage = errorMessage
        self.restoreMessage = restoreMessage
        self.onPauseWarmth = onPauseWarmth
        self.onResumeWarmth = onResumeWarmth
        self.onApply = onApply
        self.onRevert = onRevert
        self.onRestoreDefaults = onRestoreDefaults
        self.onRestorePreApp = onRestorePreApp
        self.onRetryReload = onRetryReload
        self.onQuit = onQuit
    }

    private var isUnsaved: Bool {
        draftSettings != savedSettings
    }

    private var originalBackupPathText: String {
        switch state {
        case .installed(let manifest), .outdatedRuntime(let manifest), .installedRuntimeInactive(let manifest, _):
            return manifest.originalInitBackupPath
        default:
            return "~/.hammerspoon/init.lua.codex-backup-*"
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            StatusBannerView(
                state: state,
                isUnsaved: isUnsaved,
                lastAppliedAt: lastAppliedAt,
                lastReloadResult: lastReloadResult,
                errorMessage: errorMessage
            )

            if let restoreMessage = restoreMessage, !restoreMessage.isEmpty {
                Text(restoreMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            ScrollView {
                VStack(spacing: 14) {
                    StatusDashboardView(
                        statusMonitor: statusMonitor,
                        savedSettings: savedSettings,
                        onPause: onPauseWarmth,
                        onResume: onResumeWarmth
                    )

                    Divider()

                    WarmthSectionView(
                        draftSettings: $draftSettings,
                        showAdvancedWarmth: $showAdvancedWarmth,
                        newBuiltInName: $newBuiltInName
                    )

                    Divider()

                    ZoomSectionView(draftSettings: $draftSettings)

                    Divider()

                    ActionsSectionView(
                        state: state,
                        isUnsaved: isUnsaved,
                        onApply: onApply,
                        onRevert: onRevert,
                        onRestoreDefaults: onRestoreDefaults,
                        onRestorePreApp: { showRestoreConfirmation = true },
                        onRetryReload: onRetryReload,
                        onQuit: onQuit
                    )
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .frame(width: 480, height: 580)
        .alert("Confirm Pre-App Restoration", isPresented: $showRestoreConfirmation) {
            Button("Confirm Restore", role: .destructive) {
                onRestorePreApp()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This will restore your original pre-app configuration.

            • Original baseline backup source:
              \(originalBackupPathText)

            • Planned pre-restore safety backup destination:
              ~/.hammerspoon/init.lua.pre-restore-backup-YYYYMMDD-HHMMSS

            Existing backups will remain untouched. Are you sure you want to proceed?
            """)
        }
    }
}

private struct WarmthSectionView: View {
    @Binding var draftSettings: Settings
    @Binding var showAdvancedWarmth: Bool
    @Binding var newBuiltInName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("External Display Warmth", systemImage: "sun.max.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.orange)

                Spacer()

                Toggle("", isOn: $draftSettings.warmth.enabled)
                    .toggleStyle(.switch)
            }

            if draftSettings.warmth.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Schedule Mode:", selection: $draftSettings.warmth.scheduleMode) {
                        ForEach(ScheduleMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Color Temperature:")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(draftSettings.warmth.temperatureK) K")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))

                            Button("Reset") {
                                draftSettings.warmth.temperatureK = WarmthSettings.default.temperatureK
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.borderless)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(draftSettings.warmth.temperatureK) },
                                set: { draftSettings.warmth.temperatureK = Int($0) }
                            ),
                            in: 3000...6500,
                            step: 50
                        )
                    }

                    DisclosureGroup("Advanced External Display Settings", isExpanded: $showAdvancedWarmth) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Refresh Interval:")
                                    .font(.system(size: 11))
                                Spacer()
                                Text("\(draftSettings.warmth.refreshIntervalSeconds) s")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(draftSettings.warmth.refreshIntervalSeconds) },
                                    set: { draftSettings.warmth.refreshIntervalSeconds = Int($0) }
                                ),
                                in: 15...300,
                                step: 5
                            )

                            HStack {
                                Text("Display Debounce:")
                                    .font(.system(size: 11))
                                Spacer()
                                Text(String(format: "%.1f s", draftSettings.warmth.displayDebounceSeconds))
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            Slider(
                                value: $draftSettings.warmth.displayDebounceSeconds,
                                in: 0.5...10.0,
                                step: 0.5
                            )

                            HStack(spacing: 8) {
                                Text("Fallback Lat:")
                                    .font(.system(size: 11))
                                TextField("Lat", value: $draftSettings.warmth.fallbackLatitude, format: .number)
                                    .textFieldStyle(.roundedBorder)

                                Text("Long:")
                                    .font(.system(size: 11))
                                TextField("Long", value: $draftSettings.warmth.fallbackLongitude, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Built-in Display Names (Untouched):")
                                    .font(.system(size: 11, weight: .semibold))

                                ForEach(draftSettings.warmth.builtInDisplayNames, id: \.self) { name in
                                    HStack {
                                        Text("• \(name)")
                                            .font(.system(size: 10, design: .monospaced))
                                        Spacer()
                                        Button(action: {
                                            draftSettings.warmth.builtInDisplayNames.removeAll { $0 == name }
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }

                                HStack {
                                    TextField("Add display name...", text: $newBuiltInName)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Add") {
                                        let trimmed = newBuiltInName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty && !draftSettings.warmth.builtInDisplayNames.contains(trimmed) {
                                            draftSettings.warmth.builtInDisplayNames.append(trimmed)
                                            newBuiltInName = ""
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .padding(.top, 4)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }
}

private struct ZoomSectionView: View {
    @Binding var draftSettings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Command + Scroll Zoom", systemImage: "magnifyingglass.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)

                Spacer()

                Toggle("", isOn: $draftSettings.zoom.enabled)
                    .toggleStyle(.switch)
            }

            if draftSettings.zoom.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Direction:", selection: $draftSettings.zoom.direction) {
                        ForEach(ZoomDirection.allCases) { dir in
                            Text(dir.displayName).tag(dir)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Minimum Notch Delta:")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f", draftSettings.zoom.minDelta))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        Slider(value: $draftSettings.zoom.minDelta, in: 0.01...1.00, step: 0.01)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Zoom Debounce:")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f s", draftSettings.zoom.debounceSeconds))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        Slider(value: $draftSettings.zoom.debounceSeconds, in: 0.00...0.50, step: 0.01)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }
}

private struct ActionsSectionView: View {
    let state: IntegrationState
    let isUnsaved: Bool
    let onApply: () -> Void
    let onRevert: () -> Void
    let onRestoreDefaults: () -> Void
    let onRestorePreApp: () -> Void
    let onRetryReload: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if case .installedRuntimeInactive = state {
                Button(action: onRetryReload) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("Retry Reload & Verify Runtime")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            HStack(spacing: 10) {
                Button(action: onApply) {
                    HStack {
                        Spacer()
                        Text("Apply & Reload")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Revert Unapplied", action: onRevert)
                    .buttonStyle(.bordered)
                    .disabled(!isUnsaved)
            }

            HStack(spacing: 10) {
                Button("Restore Defaults", action: onRestoreDefaults)
                    .buttonStyle(.bordered)

                Button("Restore Pre-App Config", action: onRestorePreApp)
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)

                Spacer()

                Button("Quit", action: onQuit)
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
            }
        }
    }
}
