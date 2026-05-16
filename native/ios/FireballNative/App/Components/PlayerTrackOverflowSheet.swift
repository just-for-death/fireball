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

    private var selectedSleepLabel: String? {
        guard let end = viewModel.sleepTimerEnd else { return nil }
        let remainingMin = Int(end.timeIntervalSince(sleepTick) / 60)
        guard remainingMin > 0 else { return nil }
        switch remainingMin {
        case ...18: return "15m"
        case ...33: return "30m"
        case ...48: return "45m"
        default: return "60m"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ActionSheetMetrics.sectionSpacing) {
                Text("Track options")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                trackHeader

                ActionSheetSectionCard {
                    ActionSheetRowButton(title: "Play next", systemImage: "forward.end.fill", inset: true, action: onPlayNext)
                    ActionSheetRowButton(
                        title: "Add to queue",
                        systemImage: "text.line.last.and.arrowtriangle.forward",
                        inset: true,
                        action: onAddToQueue
                    )
                    ActionSheetRowButton(
                        title: favoriteLabel,
                        systemImage: viewModel.isFavorite(track) ? "heart.fill" : "heart",
                        inset: true,
                        action: onToggleFavorite
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    ActionSheetSectionLabel(title: "Sleep")
                    if let sleepStatus {
                        Text(sleepStatus)
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .padding(.leading, 4)
                    }
                    ActionSheetSectionCard {
                        ActionSheetChipRow(
                            labels: ["15m", "30m", "45m", "60m", "Clear"],
                            selectedLabel: selectedSleepLabel,
                            onSelect: { label in
                                switch label {
                                case "15m": viewModel.setSleepTimer(minutes: 15)
                                case "30m": viewModel.setSleepTimer(minutes: 30)
                                case "45m": viewModel.setSleepTimer(minutes: 45)
                                case "60m": viewModel.setSleepTimer(minutes: 60)
                                default: viewModel.setSleepTimer(minutes: nil)
                                }
                            }
                        )
                        ActionSheetToggleRow(
                            title: "Sleep after current track",
                            subtitle: "Pause when this song ends",
                            isOn: Binding(
                                get: { viewModel.sleepAfterCurrent },
                                set: { viewModel.setSleepAfterCurrent($0) }
                            ),
                            inset: true
                        )
                    }
                }

                ActionSheetSectionCard {
                    ActionSheetRowButton(
                        title: "View artist catalog",
                        systemImage: "person.crop.circle",
                        inset: true,
                        action: onSeeArtist
                    )
                    ActionSheetRowButton(title: followLabel, systemImage: "person.badge.plus", inset: true) {
                        if viewModel.isArtistFollowed(artistName: track.artist) {
                            onUnfollowArtist()
                        } else {
                            onFollowArtist()
                        }
                    }
                }

                if !playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ActionSheetSectionLabel(title: "Add to playlist")
                        ActionSheetSectionCard {
                            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, pl in
                                let alreadyListed = pl.videos.contains(where: { $0.effectiveId == track.effectiveId })
                                ActionSheetRowButton(
                                    title: pl.title,
                                    systemImage: "music.note.list",
                                    subtitle: alreadyListed ? "Already in playlist" : nil,
                                    disabled: alreadyListed,
                                    inset: true
                                ) {
                                    if !alreadyListed { onAddToPlaylist(pl.id) }
                                }
                                if index < playlists.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                }

                ActionSheetPrimaryButton(title: "Done", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            if viewModel.sleepTimerEnd != nil {
                sleepTick = now
            }
        }
    }

    private var trackHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
                }
            }
            .frame(width: 64, height: 64)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
