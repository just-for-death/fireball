import XCTest
@testable import FireballNativeCore

final class PlaybackAdvanceRulesTests: XCTestCase {
    func testAfterTrackFinishedRepeatOneRestarts() {
        let decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex: 2,
            queueSize: 5,
            repeatMode: .one,
            shuffled: false,
            queueModeRepeat: false,
            pickShuffleIndex: { _ in nil }
        )
        XCTAssertEqual(decision, .restartCurrent)
    }

    func testAfterTrackFinishedShufflePicksOtherIndex() {
        let decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex: 0,
            queueSize: 3,
            repeatMode: .off,
            shuffled: true,
            queueModeRepeat: false,
            pickShuffleIndex: { choices in choices.first { $0 == 2 } }
        )
        XCTAssertEqual(decision, .jumpTo(2))
    }

    func testAfterTrackFinishedQueueModeRepeatWrapsAtTail() {
        let decision = PlaybackAdvanceRules.afterTrackFinished(
            currentIndex: 2,
            queueSize: 3,
            repeatMode: .off,
            shuffled: false,
            queueModeRepeat: true,
            pickShuffleIndex: { _ in nil }
        )
        XCTAssertEqual(decision, .jumpTo(0))
    }

    func testUserPressedNextRepeatAllWrapsAtTail() {
        let decision = PlaybackAdvanceRules.userPressedNext(
            currentIndex: 4,
            queueSize: 5,
            repeatMode: .all,
            shuffled: false,
            queueModeRepeat: false,
            pickShuffleIndex: { _ in nil }
        )
        XCTAssertEqual(decision, .jumpTo(0))
    }

    func testUserPressedPreviousRepeatOneRestarts() {
        let decision = PlaybackAdvanceRules.userPressedPrevious(
            currentIndex: 1,
            positionSeconds: 10,
            repeatMode: .one,
            shuffled: false,
            queueSize: 5,
            pickShuffleIndex: { _ in nil }
        )
        XCTAssertEqual(decision, .restartCurrent)
    }
}
