import Foundation

public enum ScheduleMode: String, Codable, CaseIterable, Identifiable {
    case sunsetToSunrise = "sunsetToSunrise"
    case alwaysWarm = "alwaysWarm"
    case alwaysNeutral = "alwaysNeutral"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sunsetToSunrise: return "Sunset to sunrise"
        case .alwaysWarm: return "Always warm"
        case .alwaysNeutral: return "Always neutral"
        }
    }
}

public enum ZoomDirection: String, Codable, CaseIterable, Identifiable {
    case scrollUpZoomsIn = "scrollUpZoomsIn"
    case scrollUpZoomsOut = "scrollUpZoomsOut"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scrollUpZoomsIn: return "Scroll up zooms in"
        case .scrollUpZoomsOut: return "Scroll up zooms out (reversed)"
        }
    }
}

public struct WarmthSettings: Codable, Equatable {
    public var enabled: Bool
    public var scheduleMode: ScheduleMode
    public var temperatureK: Int
    public var refreshIntervalSeconds: Int
    public var displayDebounceSeconds: Double
    public var fallbackLatitude: Double
    public var fallbackLongitude: Double
    public var builtInDisplayNames: [String]
    public var pauseUntilEpoch: Double?

    public static let defaultBuiltInDisplayNames = [
        "Built-in Retina Display",
        "Color LCD",
        "Liquid Retina XDR Display"
    ]

    public static let `default` = WarmthSettings(
        enabled: true,
        scheduleMode: .sunsetToSunrise,
        temperatureK: 4300,
        refreshIntervalSeconds: 60,
        displayDebounceSeconds: 2.0,
        fallbackLatitude: -23.5505,
        fallbackLongitude: -46.6333,
        builtInDisplayNames: defaultBuiltInDisplayNames,
        pauseUntilEpoch: nil
    )

    public func validate() throws {
        guard temperatureK >= 3000 && temperatureK <= 6500 else {
            throw SettingsValidationError.outOfRange("Warmth temperature must be between 3,000 K and 6,500 K.")
        }
        guard refreshIntervalSeconds >= 15 && refreshIntervalSeconds <= 300 else {
            throw SettingsValidationError.outOfRange("Refresh interval must be between 15 and 300 seconds.")
        }
        guard displayDebounceSeconds >= 0.5 && displayDebounceSeconds <= 10.0 else {
            throw SettingsValidationError.outOfRange("Display debounce must be between 0.5 and 10.0 seconds.")
        }
        guard fallbackLatitude >= -90.0 && fallbackLatitude <= 90.0 else {
            throw SettingsValidationError.outOfRange("Fallback latitude must be between -90.0 and 90.0.")
        }
        guard fallbackLongitude >= -180.0 && fallbackLongitude <= 180.0 else {
            throw SettingsValidationError.outOfRange("Fallback longitude must be between -180.0 and 180.0.")
        }
    }
}

public struct ZoomSettings: Codable, Equatable {
    public var enabled: Bool
    public var minDelta: Double
    public var debounceSeconds: Double
    public var direction: ZoomDirection

    public static let `default` = ZoomSettings(
        enabled: true,
        minDelta: 0.08,
        debounceSeconds: 0.05,
        direction: .scrollUpZoomsIn
    )

    public func validate() throws {
        guard minDelta >= 0.01 && minDelta <= 1.00 else {
            throw SettingsValidationError.outOfRange("Zoom minimum delta must be between 0.01 and 1.00.")
        }
        guard debounceSeconds >= 0.00 && debounceSeconds <= 0.50 else {
            throw SettingsValidationError.outOfRange("Zoom debounce must be between 0.00 and 0.50 seconds.")
        }
    }
}

public struct Settings: Codable, Equatable {
    public var version: Int
    public var warmth: WarmthSettings
    public var zoom: ZoomSettings

    public static let `default` = Settings(
        version: 1,
        warmth: .default,
        zoom: .default
    )

    public func validate() throws {
        try warmth.validate()
        try zoom.validate()
    }
}

public enum SettingsValidationError: LocalizedError, Equatable {
    case outOfRange(String)
    case malformedJSON(String)

    public var errorDescription: String? {
        switch self {
        case .outOfRange(let msg): return msg
        case .malformedJSON(let msg): return msg
        }
    }
}
