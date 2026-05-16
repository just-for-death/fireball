import Foundation

/// Client-side scrobble timing (ListenBrainz + Last.fm).
/// Fires when **either** percent of the track or max seconds is reached first.
/// Tracks shorter than `minTrackSeconds` are never scrobbled.
enum ScrobbleRules {
    static let defaultMinTrackSeconds = 30
    static let defaultPercent = 25
    static let defaultMaxSeconds = 40

    static func shouldScrobble(
        positionMs: Int64,
        durationMs: Int64,
        percent: Int,
        maxSeconds: Int,
        minTrackSeconds: Int = defaultMinTrackSeconds
    ) -> Bool {
        guard durationMs > 0 else { return false }
        let minMs = Int64(max(1, minTrackSeconds)) * 1000
        guard durationMs >= minMs else { return false }
        let pct = min(100, max(0, percent))
        let maxSec = max(0, maxSeconds)
        let byPercent = pct > 0 && positionMs >= durationMs * Int64(pct) / 100
        let byMaxSec = maxSec > 0 && positionMs >= Int64(maxSec) * 1000
        return byPercent || byMaxSec
    }

    static func shouldScrobble(
        positionSeconds: Double,
        durationSeconds: Double,
        percent: Int,
        maxSeconds: Int,
        minTrackSeconds: Int = defaultMinTrackSeconds
    ) -> Bool {
        guard durationSeconds > 0 else { return false }
        return shouldScrobble(
            positionMs: Int64(positionSeconds * 1000),
            durationMs: Int64(durationSeconds * 1000),
            percent: percent,
            maxSeconds: maxSeconds,
            minTrackSeconds: minTrackSeconds
        )
    }
}
