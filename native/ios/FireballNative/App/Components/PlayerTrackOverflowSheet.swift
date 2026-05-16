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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(Color.secondary.opacity(0.25))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Button { onPlayNext() } label: {
                        Label("Play next", systemImage: "forward.end.fill")
                    }
                    Button { onAddToQueue() } label: {
                        Label("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    Button { onToggleFavorite() } label: {
                        Label(favoriteLabel, systemImage: viewModel.isFavorite(track) ? "heart.fill" : "heart")
                    }
                }

                Section {
                    Button { onSeeArtist() } label: {
                        Label("View artist catalog", systemImage: "person.crop.circle")
                    }
                    Button {
                        if viewModel.isArtistFollowed(artistName: track.artist) {
                            onUnfollowArtist()
                        } else {
                            onFollowArtist()
                        }
                    } label: {
                        Label(followLabel, systemImage: "person.badge.plus")
                    }
                }

                if !playlists.isEmpty {
                    Section {
                        ForEach(playlists, id: \.id) { pl in
                            let alreadyListed = pl.videos.contains(where: { $0.effectiveId == track.effectiveId })
                            Button {
                                if !alreadyListed { onAddToPlaylist(pl.id) }
                            } label: {
                                HStack {
                                    Label(pl.title, systemImage: "music.note.list")
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
                        Text("Tap several playlists if you like, then Done.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Track options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
