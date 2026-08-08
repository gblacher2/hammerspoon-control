import XCTest
@testable import HammerspoonControl

final class StatusMonitorTests: XCTestCase {

    func testSolarCalculatorReturnsValidTimesForSaoPaulo() {
        let (sunrise, sunset) = SolarCalculator.calculateTimes(
            latitude: -23.5505,
            longitude: -46.6333,
            date: Date()
        )

        XCTAssertNotNil(sunrise)
        XCTAssertNotNil(sunset)
        if let sunrise = sunrise, let sunset = sunset {
            XCTAssertLessThan(sunrise, sunset, "Sunrise should be before sunset")
        }
    }

    func testRuntimeStatusDecoding() throws {
        let json = """
        {
            "updatedAt": 1754600000,
            "warmthEnabled": true,
            "scheduleMode": "sunsetToSunrise",
            "nighttime": true,
            "isPaused": false,
            "pauseUntilEpoch": null,
            "locationSource": "macOS Location Services",
            "temperatureK": 4300,
            "sunriseEpoch": 1754560000,
            "sunsetEpoch": 1754605000,
            "displays": [
                {
                    "name": "Built-in Retina Display",
                    "isBuiltIn": true,
                    "gammaApplied": "neutral"
                },
                {
                    "name": "DELL U2720Q",
                    "isBuiltIn": false,
                    "gammaApplied": "warm (4300K)"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: json)
        XCTAssertEqual(decoded.updatedAt, 1754600000)
        XCTAssertTrue(decoded.nighttime)
        XCTAssertFalse(decoded.isPaused)
        XCTAssertEqual(decoded.displays.count, 2)
        XCTAssertTrue(decoded.displays[0].isBuiltIn)
        XCTAssertFalse(decoded.displays[1].isBuiltIn)
    }

    @MainActor
    func testStatusMonitorInitializationAndProperties() {
        let tempDir = NSTemporaryDirectory()
        let monitor = StatusMonitor(configDir: tempDir)

        XCTAssertFalse(monitor.isPaused)
        XCTAssertEqual(monitor.remainingPauseSeconds, 0)
    }
}
