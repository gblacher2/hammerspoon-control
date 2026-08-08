import XCTest
@testable import HammerspoonControl

final class SettingsTests: XCTestCase {

    func testDefaultSettingsMatchesCurrentBehaviorBaseline() {
        let settings = Settings.default

        XCTAssertTrue(settings.warmth.enabled)
        XCTAssertEqual(settings.warmth.scheduleMode, .sunsetToSunrise)
        XCTAssertEqual(settings.warmth.temperatureK, 4300)
        XCTAssertEqual(settings.warmth.refreshIntervalSeconds, 60)
        XCTAssertEqual(settings.warmth.displayDebounceSeconds, 2.0)
        XCTAssertEqual(settings.warmth.fallbackLatitude, -23.5505)
        XCTAssertEqual(settings.warmth.fallbackLongitude, -46.6333)
        XCTAssertEqual(settings.warmth.builtInDisplayNames, [
            "Built-in Retina Display",
            "Color LCD",
            "Liquid Retina XDR Display"
        ])

        XCTAssertTrue(settings.zoom.enabled)
        XCTAssertEqual(settings.zoom.minDelta, 0.08)
        XCTAssertEqual(settings.zoom.debounceSeconds, 0.05)
        XCTAssertEqual(settings.zoom.direction, .scrollUpZoomsIn)
    }

    func testSettingsRoundTripping() throws {
        let settings = Settings.default
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(Settings.self, from: data)

        XCTAssertEqual(settings, decoded)
    }

    func testPauseUntilEpochRoundTrips() throws {
        var settings = Settings.default
        let futureEpoch = Date().timeIntervalSince1970 + 3600
        settings.warmth.pauseUntilEpoch = futureEpoch

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(Settings.self, from: data)

        XCTAssertEqual(decoded.warmth.pauseUntilEpoch, futureEpoch)
    }

    func testValidationRejectsOutOfRangeTemperature() {
        var settings = Settings.default
        settings.warmth.temperatureK = 2000
        XCTAssertThrowsError(try settings.validate())

        settings.warmth.temperatureK = 7000
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidationRejectsOutOfRangeRefreshInterval() {
        var settings = Settings.default
        settings.warmth.refreshIntervalSeconds = 5
        XCTAssertThrowsError(try settings.validate())

        settings.warmth.refreshIntervalSeconds = 500
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidationRejectsOutOfRangeDisplayDebounce() {
        var settings = Settings.default
        settings.warmth.displayDebounceSeconds = 0.1
        XCTAssertThrowsError(try settings.validate())

        settings.warmth.displayDebounceSeconds = 20.0
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidationRejectsOutOfRangeZoomMinDelta() {
        var settings = Settings.default
        settings.zoom.minDelta = 0.00
        XCTAssertThrowsError(try settings.validate())

        settings.zoom.minDelta = 1.50
        XCTAssertThrowsError(try settings.validate())
    }

    func testValidationRejectsOutOfRangeZoomDebounce() {
        var settings = Settings.default
        settings.zoom.debounceSeconds = -0.1
        XCTAssertThrowsError(try settings.validate())

        settings.zoom.debounceSeconds = 1.0
        XCTAssertThrowsError(try settings.validate())
    }

    func testMalformedJSONThrows() {
        let invalidJSON = "{\"warmth\": \"invalid\"}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: invalidJSON))
    }
}
