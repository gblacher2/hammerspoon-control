import Foundation
import Combine

@MainActor
public class StatusMonitor: ObservableObject {
    @Published public private(set) var runtimeStatus: RuntimeStatus = .default
    @Published public private(set) var remainingPauseSeconds: Int = 0
    @Published public private(set) var iconName: String = "sun.max.fill"
    @Published public private(set) var statusText: String = "Neutral"

    private var timer: AnyCancellable?
    private let configDir: String

    public init(configDir: String? = nil) {
        self.configDir = configDir ?? StatusMonitor.defaultConfigDir
        self.refreshStatus()

        self.timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStatus()
            }
    }

    public static var defaultConfigDir: String {
        if let custom = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_CONFIG_DIR"], !custom.isEmpty {
            return custom
        }
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".hammerspoon/hammerspoon-control")
    }

    public var isPaused: Bool {
        if let epoch = runtimeStatus.pauseUntilEpoch, epoch > Date().timeIntervalSince1970 {
            return true
        }
        return runtimeStatus.isPaused
    }

    public func refreshStatus() {
        let statusFile = (configDir as NSString).appendingPathComponent("status.json")
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: statusFile),
           let data = try? Data(contentsOf: URL(fileURLWithPath: statusFile)),
           let decoded = try? JSONDecoder().decode(RuntimeStatus.self, from: data) {
            self.runtimeStatus = decoded
        }

        updateComputedProperties()
    }

    private func updateComputedProperties() {
        let now = Date().timeIntervalSince1970

        if let epoch = runtimeStatus.pauseUntilEpoch, epoch > now {
            let remaining = Int(ceil(epoch - now))
            self.remainingPauseSeconds = max(0, remaining)
            self.iconName = "pause.circle.fill"
            self.statusText = "Warmth Paused (\(formatRemainingTime(seconds: remaining)))"
            return
        }

        self.remainingPauseSeconds = 0

        if !runtimeStatus.warmthEnabled || runtimeStatus.scheduleMode == "alwaysNeutral" {
            self.iconName = "moon.slash"
            self.statusText = "Warmth Disabled"
        } else if runtimeStatus.scheduleMode == "alwaysWarm" || runtimeStatus.nighttime {
            self.iconName = "moon.stars.fill"
            self.statusText = "Night Warmth Active (\(runtimeStatus.temperatureK)K)"
        } else {
            self.iconName = "sun.max.fill"
            self.statusText = "Daytime Neutral"
        }
    }

    private func formatRemainingTime(seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hours)h \(mins)m"
        } else {
            let mins = max(1, seconds / 60)
            return "\(mins)m"
        }
    }
}
