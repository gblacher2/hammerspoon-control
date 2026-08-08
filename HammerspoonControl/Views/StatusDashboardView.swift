import SwiftUI

@MainActor
public struct StatusDashboardView: View {
    @ObservedObject var statusMonitor: StatusMonitor
    let savedSettings: Settings
    let onPause: (Int) -> Void
    let onResume: () -> Void

    public init(
        statusMonitor: StatusMonitor,
        savedSettings: Settings,
        onPause: @escaping (Int) -> Void,
        onResume: @escaping () -> Void
    ) {
        self.statusMonitor = statusMonitor
        self.savedSettings = savedSettings
        self.onPause = onPause
        self.onResume = onResume
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Solar Phase & Cycle Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: statusMonitor.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(solarIconColor)
                    Text("Solar Cycle & Status")
                        .font(.headline)
                    Spacer()
                    Text(statusMonitor.statusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(solarBadgeBackgroundColor)
                        .foregroundColor(solarBadgeForegroundColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sunrise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatEpoch(statusMonitor.runtimeStatus.sunriseEpoch) ?? fallbackSunrise)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sunset")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatEpoch(statusMonitor.runtimeStatus.sunsetEpoch) ?? fallbackSunset)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Location Source")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(statusMonitor.runtimeStatus.locationSource)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Quick Pause Warmth Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .medium))
                    Text("Quick Pause Warmth")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                if statusMonitor.isPaused {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Warmth Temporarily Paused")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("External monitors set to neutral gamma")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Pause 30m") { onPause(30) }
                            .buttonStyle(.bordered)
                            .font(.caption)

                        Button("Pause 1h") { onPause(60) }
                            .buttonStyle(.bordered)
                            .font(.caption)

                        Button("Pause 2h") { onPause(120) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Connected Displays Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "display.2")
                        .font(.system(size: 13, weight: .medium))
                    Text("Connected Displays")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(displaysList.count) Screen\(displaysList.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if displaysList.isEmpty {
                    Text("No external monitors detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(displaysList) { display in
                            HStack {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    .font(.caption)
                                    .foregroundColor(display.isBuiltIn ? .secondary : .accentColor)

                                Text(display.name)
                                    .font(.caption)
                                    .fontWeight(display.isBuiltIn ? .regular : .medium)

                                Spacer()

                                Text(display.gammaApplied)
                                    .font(.caption2)
                                    .foregroundColor(display.gammaApplied.contains("warm") ? .orange : .secondary)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var displaysList: [DisplayInfo] {
        if !statusMonitor.runtimeStatus.displays.isEmpty {
            return statusMonitor.runtimeStatus.displays
        }
        return [
            DisplayInfo(name: "Built-in Display", isBuiltIn: true, gammaApplied: "managed by macOS"),
            DisplayInfo(name: "External Monitor", isBuiltIn: false, gammaApplied: statusMonitor.runtimeStatus.nighttime && !statusMonitor.isPaused ? "warm (\(savedSettings.warmth.temperatureK)K)" : "neutral")
        ]
    }

    private var solarIconColor: Color {
        if statusMonitor.isPaused { return .orange }
        if statusMonitor.runtimeStatus.nighttime { return .indigo }
        return .orange
    }

    private var solarBadgeBackgroundColor: Color {
        if statusMonitor.isPaused { return Color.orange.opacity(0.15) }
        if statusMonitor.runtimeStatus.nighttime { return Color.indigo.opacity(0.15) }
        return Color.orange.opacity(0.15)
    }

    private var solarBadgeForegroundColor: Color {
        if statusMonitor.isPaused { return .orange }
        if statusMonitor.runtimeStatus.nighttime { return .indigo }
        return .orange
    }

    private func formatEpoch(_ epoch: Double?) -> String? {
        guard let epoch = epoch, epoch > 0 else { return nil }
        let date = Date(timeIntervalSince1970: epoch)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var fallbackSunrise: String {
        let (sunrise, _) = SolarCalculator.calculateTimes(
            latitude: savedSettings.warmth.fallbackLatitude,
            longitude: savedSettings.warmth.fallbackLongitude
        )
        if let s = sunrise {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: s)
        }
        return "--:--"
    }

    private var fallbackSunset: String {
        let (_, sunset) = SolarCalculator.calculateTimes(
            latitude: savedSettings.warmth.fallbackLatitude,
            longitude: savedSettings.warmth.fallbackLongitude
        )
        if let s = sunset {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: s)
        }
        return "--:--"
    }
}
