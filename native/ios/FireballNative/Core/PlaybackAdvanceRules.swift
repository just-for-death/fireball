import Foundation

/// Shared queue advance decisions for native players (parity with Android `PlaybackAdvanceRules`).
enum PlaybackRepeatMode: Equatable {
    case off
    case all
    case one
}

enum PlaybackAdvanceDecision: Equatable {
    case restartCurrent
    case jumpTo(Int)
    case stopPlayback
    case noOp
}

enum PlaybackAdvanceRules {
    static func afterTrackFinished(
        currentIndex: Int,
        queueSize: Int,
        repeatMode: PlaybackRepeatMode,
        shuffled: Bool,
        queueModeRepeat: Bool,
        pickShuffleIndex: ([Int]) -> Int?
    ) -> PlaybackAdvanceDecision {
        guard currentIndex >= 0, queueSize > 0 else { return .noOp }
        if repeatMode == .one { return .restartCurrent }
        if shuffled, queueSize > 1 {
            let choices = (0..<queueSize).filter { $0 != currentIndex }
            if let next = pickShuffleIndex(choices) { return .jumpTo(next) }
            return .noOp
        }
        if currentIndex + 1 < queueSize { return .jumpTo(currentIndex + 1) }
        if repeatMode == .all { return .jumpTo(0) }
        if queueModeRepeat { return .jumpTo(0) }
        return .stopPlayback
    }

    static func userPressedNext(
        currentIndex: Int,
        queueSize: Int,
        repeatMode: PlaybackRepeatMode,
        shuffled: Bool,
        queueModeRepeat: Bool,
        pickShuffleIndex: ([Int]) -> Int?
    ) -> PlaybackAdvanceDecision {
        guard currentIndex >= 0, queueSize > 0 else { return .noOp }
        if repeatMode == .one { return .restartCurrent }
        if shuffled, queueSize > 1 {
            let choices = (0..<queueSize).filter { $0 != currentIndex }
            if let next = pickShuffleIndex(choices) { return .jumpTo(next) }
            return .noOp
        }
        if currentIndex + 1 < queueSize { return .jumpTo(currentIndex + 1) }
        if repeatMode == .all { return .jumpTo(0) }
        if queueModeRepeat { return .jumpTo(0) }
        return .noOp
    }

    static func userPressedPrevious(
        currentIndex: Int,
        positionSeconds: Double,
        repeatMode: PlaybackRepeatMode,
        shuffled: Bool,
        queueSize: Int,
        pickShuffleIndex: ([Int]) -> Int?
    ) -> PlaybackAdvanceDecision {
        guard currentIndex >= 0, queueSize > 0 else { return .noOp }
        if repeatMode == .one { return .restartCurrent }
        if positionSeconds > 3 { return .restartCurrent }
        if shuffled, queueSize > 1 {
            let choices = (0..<queueSize).filter { $0 != currentIndex }
            if let pick = pickShuffleIndex(choices) { return .jumpTo(pick) }
            return .noOp
        }
        return .jumpTo(max(0, currentIndex - 1))
    }
}
