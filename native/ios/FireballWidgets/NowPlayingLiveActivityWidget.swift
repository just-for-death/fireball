import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct NowPlayingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.75))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: "music.note")
            }
        }
    }
}
