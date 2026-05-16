import XCTest
@testable import FireballNativeCore

final class ScrobbleRulesTests: XCTestCase {
    func testRejectsShortTracks() {
        XCTAssertFalse(ScrobbleRules.shouldScrobble(
            positionMs: 29_000,
            durationMs: 29_000,
            percent: 25,
            maxSeconds: 40
        ))
    }

    func testFiresAtPercent() {
        XCTAssertTrue(ScrobbleRules.shouldScrobble(
            positionMs: 30_000,
            durationMs: 120_000,
            percent: 25,
            maxSeconds: 0
        ))
    }

    func testFiresAtMaxSeconds() {
        XCTAssertTrue(ScrobbleRules.shouldScrobble(
            positionMs: 40_000,
            durationMs: 600_000,
            percent: 0,
            maxSeconds: 40
        ))
    }

    func testPercentZeroDoesNotAutoFire() {
        XCTAssertFalse(ScrobbleRules.shouldScrobble(
            positionMs: 5_000,
            durationMs: 120_000,
            percent: 0,
            maxSeconds: 0
        ))
    }

    func testCustomMinTrackSeconds() {
        XCTAssertTrue(ScrobbleRules.shouldScrobble(
            positionMs: 20_000,
            durationMs: 25_000,
            percent: 50,
            maxSeconds: 10,
            minTrackSeconds: 20
        ))
    }
}
