import Combine
import SwiftUI

/// Track actions from long-press on the mini player / now playing overflow button.
struct PlayerTrackOverflowSheet: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    let track: Track
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToPlaylist: (String) -> Void
    let onSeeArtist: () -> Void
    let onFollowArtist: () -> Void
    let onUnfollowArtist: () -> Void

    private var favoriteLabel: String {
        viewModel.isFavorite(track) ? "Remove from favorites" : "Add to favorites"
    }

    private var followLabel: String {
        viewModel.isArtistFollowed(artistName: track.artist) ? "Unfollow artist" : "Follow artist"
    }

    private var playlists: [Playlist] {
        viewModel.userPlaylistsForPicker()
    }

    @State private var sleepTick = Date()

    private var sleepStatus: String? {
        guard let end = viewModel.sleepTimerEnd else { return nil }
        let remaining = end.timeIntervalSince(sleepTick)
        guard remaining > 0 else { return nil }
        let total = Int(remaining)
        return String(format: "Stops in %d:%02d", total / 60, total % 60)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ActionSheetMetrics.sectionSpacing) {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.25))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    ActionSheetRowGroup {
                        SuvFadeSlideIn(delayMs: 0) {
                            ActionSheetRowButton(title: "Play next", systemImage: "forward.end.fill", action: onPlayNext)
                        }
                        SuvFadeSlideIn(delayMs: 40) {
                            ActionSheetRowButton(
                                title: "Add to queue",
                                systemImage: "text.line.last.and.arrowtriangle.forward",
                                action: onAddToQueue
                            )
                        }
                        SuvFadeSlideIn(delayMs: 80) {
                            ActionSheetRowButton(
                                title: favoriteLabel,
                                systemImage: viewModel.isFavorite(track) ? "heart.fill" : "heart",
                                action: onToggleFavorite
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: ActionSheetMetrics.rowSpacing) {
                        ActionSheetSectionLabel(title: "Sleep")

                        if let sleepStatus {
                            Text(sleepStatus)
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.leading, 4)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["15m", "30m", "45m", "60m", "Clear"], id: \.self) { label in
                                    Button(label) {
                                        switch label {
                                        case "15m": viewModel.setSleepTimer(minutes: 15)
                                        case "30m": viewModel.setSleepTimer(minutes: 30)
                                        case "45m": viewModel.setSleepTimer(minutes: 45)
                                        case "60m": viewModel.setSleepTimer(minutes: 60)
                                        default: viewModel.setSleepTimer(minutes: nil)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        ActionSheetToggleRow(
                            title: "Sleep after current track",
                            subtitle: "Pause when this song ends",
                            isOn: Binding(
                                get: { viewModel.sleepAfterCurrent },
                                set: { viewModel.setSleepAfterCurrent($0) }
                            )
                        )
                    }

                    ActionSheetRowGroup {
                        SuvFadeSlideIn(delayMs: 120) {
                            ActionSheetRowButton(
                                title: "View artist catalog",
                                systemImage: "person.crop.circle",
                                action: onSeeArtist
                            )
                        }
                        SuvFadeSlideIn(delayMs: 160) {
                            ActionSheetRowButton(title: followLabel, systemImage: "person.badge.plus") {
                                if viewModel.isArtistFollowed(artistName: track.artist) {
                                    onUnfollowArtist()
                                } else {
                                    onFollowArtist()
                                }
                            }
                        }
                    }

                    if !playlists.isEmpty {
                        VStack(alignment: .leading, spacing: ActionSheetMetrics.rowSpacing) {
                            ActionSheetSectionLabel(title: "Add to playlist")

                            ActionSheetRowGroup {
                                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, pl in
                                    let alreadyListed = pl.videos.contains(where: { $0.effectiveId == track.effectiveId })
                                    SuvFadeSlideIn(delayMs: 200 + index * 40) {
                                        ActionSheetRowButton(
                                            title: pl.title,
                                            systemImage: "music.note.list",
                                            subtitle: alreadyListed ? "Already in playlist" : nil,
                                            disabled: alreadyListed
                                        ) {
                                            if !alreadyListed { onAddToPlaylist(pl.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ActionSheetRowGroup {
                        SuvFadeSlideIn(delayMs: 80) {
                            ActionSheetRowButton(
                                title: "Done",
                                systemImage: "xmark.circle.fill",
                                role: .cancel
                            ) {
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Track options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            if viewModel.sleepTimerEnd != nil {
                sleepTick = now
            }
        }
    }
}
