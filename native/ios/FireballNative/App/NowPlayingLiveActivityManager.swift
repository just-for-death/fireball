import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
enum NowPlayingLiveActivityManager {
    private static var activity: Activity<NowPlayingActivityAttributes>?

    static func update(
        enabled: Bool,
        title: String,
        artist: String,
        isPlaying: Bool
    ) {
        guard enabled else {
            end()
            return
        }
        let state = NowPlayingActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: isPlaying
        )
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let attrs = NowPlayingActivityAttributes()
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    static func end() {
        guard let activity else { return }
        let current = activity
        self.activity = nil
        Task {
            await current.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#else
enum NowPlayingLiveActivityManager {
    static func update(enabled: Bool, title: String, artist: String, isPlaying: Bool) {}
    static func end() {}
}
#endif
