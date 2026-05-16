import SwiftUI

/// Track actions from long-press on the mini player / now playing metadata.
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

    private var favoriteLabel: String {
        viewModel.isFavorite(track) ? "Remove from favorites" : "Add to favorites"
    }

    private var playlists: [Playlist] {
        viewModel.userPlaylistsForPicker()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Play next", action: onPlayNext)
                    Button("Add to queue", action: onAddToQueue)
                    Button(favoriteLabel, action: onToggleFavorite)
                    Button("View artist catalog", action: onSeeArtist)
                    Button("Follow artist", action: onFollowArtist)
                }
                if !playlists.isEmpty {
                    Section {
                        ForEach(playlists, id: \.id) { pl in
                            let alreadyListed = pl.videos.contains(where: { $0.effectiveId == track.effectiveId })
                            Button {
                                if !alreadyListed { onAddToPlaylist(pl.id) }
                            } label: {
                                HStack {
                                    Text(pl.title)
                                    Spacer()
                                    if alreadyListed {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(alreadyListed)
                        }
                    } header: {
                        Text("Add to playlist")
                    } footer: {
                        Text("Choose multiple playlists if you like, then tap Done.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(track.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
