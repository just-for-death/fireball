import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shared between the app (Activity.request) and FireballWidgets (ActivityConfiguration).
@available(iOS 16.1, *)
public struct NowPlayingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var artist: String
        public var isPlaying: Bool

        public init(title: String, artist: String, isPlaying: Bool) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
        }
    }

    public init() {}
}
#endif
