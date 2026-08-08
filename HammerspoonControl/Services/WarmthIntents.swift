import Foundation
import AppIntents

public struct PauseWarmthIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pause Warmth (1 Hour)"
    public static var description = IntentDescription("Temporarily sets external monitor gamma to neutral for 1 hour.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let integrationService = IntegrationService()
        var settings = integrationService.loadCurrentSettings()
        settings.warmth.pauseUntilEpoch = Date().timeIntervalSince1970 + 3600
        _ = try integrationService.applySettings(settings)
        return .result()
    }
}

public struct ResumeWarmthIntent: AppIntent {
    public static var title: LocalizedStringResource = "Resume Warmth"
    public static var description = IntentDescription("Resumes normal scheduled warmth for external monitors.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let integrationService = IntegrationService()
        var settings = integrationService.loadCurrentSettings()
        settings.warmth.pauseUntilEpoch = nil
        _ = try integrationService.applySettings(settings)
        return .result()
    }
}

public struct ToggleWarmthIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Warmth"
    public static var description = IntentDescription("Toggles display warmth enabled state on or off.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let integrationService = IntegrationService()
        var settings = integrationService.loadCurrentSettings()
        settings.warmth.enabled.toggle()
        _ = try integrationService.applySettings(settings)
        return .result()
    }
}
