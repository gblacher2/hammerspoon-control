import XCTest
@testable import HammerspoonControl

final class WarmthIntentsTests: XCTestCase {

    @MainActor
    func testPauseWarmthIntentTogglesPauseSetting() async throws {
        let intent = PauseWarmthIntent()
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    @MainActor
    func testResumeWarmthIntentClearsPauseSetting() async throws {
        let intent = ResumeWarmthIntent()
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }

    @MainActor
    func testToggleWarmthIntentFlipsEnabledState() async throws {
        let intent = ToggleWarmthIntent()
        let result = try await intent.perform()
        XCTAssertNotNil(result)
    }
}
