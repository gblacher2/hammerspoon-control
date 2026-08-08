import Foundation

public struct DisplayInfo: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var isBuiltIn: Bool
    public var gammaApplied: String

    public init(name: String, isBuiltIn: Bool, gammaApplied: String) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.gammaApplied = gammaApplied
    }
}

public struct RuntimeStatus: Codable, Equatable {
    public var updatedAt: Double
    public var warmthEnabled: Bool
    public var scheduleMode: String
    public var nighttime: Bool
    public var isPaused: Bool
    public var pauseUntilEpoch: Double?
    public var locationSource: String
    public var temperatureK: Int
    public var sunriseEpoch: Double?
    public var sunsetEpoch: Double?
    public var displays: [DisplayInfo]

    public init(
        updatedAt: Double,
        warmthEnabled: Bool,
        scheduleMode: String,
        nighttime: Bool,
        isPaused: Bool,
        pauseUntilEpoch: Double?,
        locationSource: String,
        temperatureK: Int,
        sunriseEpoch: Double?,
        sunsetEpoch: Double?,
        displays: [DisplayInfo]
    ) {
        self.updatedAt = updatedAt
        self.warmthEnabled = warmthEnabled
        self.scheduleMode = scheduleMode
        self.nighttime = nighttime
        self.isPaused = isPaused
        self.pauseUntilEpoch = pauseUntilEpoch
        self.locationSource = locationSource
        self.temperatureK = temperatureK
        self.sunriseEpoch = sunriseEpoch
        self.sunsetEpoch = sunsetEpoch
        self.displays = displays
    }

    public static let `default` = RuntimeStatus(
        updatedAt: 0,
        warmthEnabled: true,
        scheduleMode: "sunsetToSunrise",
        nighttime: false,
        isPaused: false,
        pauseUntilEpoch: nil,
        locationSource: "Location Services",
        temperatureK: 4300,
        sunriseEpoch: nil,
        sunsetEpoch: nil,
        displays: []
    )
}

public struct SolarCalculator {
    public static func calculateTimes(latitude: Double, longitude: Double, date: Date = Date(), timeZone: TimeZone = .current) -> (sunrise: Date?, sunset: Date?) {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        
        let gamma = (2.0 * .pi / 365.0) * Double(dayOfYear - 1)
        let eqtime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        
        let latRad = latitude * .pi / 180.0
        let zenithRad = 90.833 * .pi / 180.0
        
        let cosHA = (cos(zenithRad) / (cos(latRad) * cos(decl))) - (tan(latRad) * tan(decl))
        guard cosHA >= -1.0 && cosHA <= 1.0 else { return (nil, nil) }
        
        let haDeg = acos(cosHA) * 180.0 / .pi
        let timeOffsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60.0
        
        let sunriseMinutes = 720.0 - 4.0 * (longitude + haDeg) - eqtime + timeOffsetMinutes
        let sunsetMinutes = 720.0 - 4.0 * (longitude - haDeg) - eqtime + timeOffsetMinutes
        
        let startOfDay = calendar.startOfDay(for: date)
        let sunriseDate = startOfDay.addingTimeInterval(sunriseMinutes * 60.0)
        let sunsetDate = startOfDay.addingTimeInterval(sunsetMinutes * 60.0)
        
        return (sunriseDate, sunsetDate)
    }
}
