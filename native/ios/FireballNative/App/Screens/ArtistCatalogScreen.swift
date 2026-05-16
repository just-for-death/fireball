import SwiftUI

private struct ExpandedAlbumDraft: Identifiable {
    let album: Album
    var id: String { album.id }
}

/// iTunes-backed artist browse (catalog + filtered local playlists), mirroring Android `ArtistDetailRoute`.
struct ArtistCatalogScreen: View {
    @EnvironmentObject private var viewModel: MainViewModel
    let appleArtistId: Int?
    let fallbackDisplayName: String

    @Environment(\.dismiss) private var dismiss

    enum Tab: Hashable {
        case songs
        case albums
        case playlists
    }

    @State private var selectedTab: Tab = .songs
    @State private var browseResult: ArtistBrowseResult?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var expandedAlbum: ExpandedAlbumDraft?
    @State private var albumTracks: [Track] = []
    @State private var albumTracksLoading = false

    private var matchedFollowedArtist: Artist? {
        viewModel.library.artists.first(where: { $0.name.caseInsensitiveCompare(browseResult?.displayName ?? fallbackDisplayName) == .orderedSame })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && browseResult == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError, browseResult == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Could not load artist")
                            .font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let browse = browseResult {
                    ScrollView {
                        VStack(spacing: 16) {
                            header(browse)

                            tabPicker

                            switch selectedTab {
                            case .songs:
                                trackList(browse.songs)
                            case .albums:
                                albumsBody(browse)
                            case .playlists:
                                playlistBody(browse)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Artist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if browseResult != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(matchedFollowedArtist == nil ? "Follow" : "Unfollow") {
                            if let existing = matchedFollowedArtist {
                                viewModel.unfollowArtist(existing.artistId)
                            } else if let browse = browseResult {
                                viewModel.followArtist(browse.displayName, artwork: browse.artworkUrl)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await load()
        }
        .sheet(item: $expandedAlbum) { wrapper in
            let album = wrapper.album
            NavigationStack {
                Group {
                    if albumTracksLoading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if albumTracks.isEmpty {
                        Text("No tracks resolved for this album.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        List(albumTracks, id: \.effectiveId) { t in
                            Button {
                                viewModel.playFromPlaylist(track: t, source: albumTracks)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.title)
                                    Text(t.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(album.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            expandedAlbum = nil
                            albumTracks = []
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Play all") {
                            viewModel.playCatalogAlbum(album)
                            expandedAlbum = nil
                        }
                        .disabled(Int(album.id) == nil)
                    }
                }
                .task {
                    guard let cid = Int(album.id) else { return }
                    albumTracksLoading = true
                    albumTracks = await viewModel.albumTracksCatalog(collectionId: cid)
                    albumTracksLoading = false
                }
            }
        }
    }

    private func header(_ browse: ArtistBrowseResult) -> some View {
        VStack(spacing: 12) {
            AsyncImage(url: URL(string: browse.artworkUrl ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.35))
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(browse.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Button("Play top songs") {
                guard let first = browse.songs.first else { return }
                viewModel.play(track: first, source: browse.songs)
            }
            .buttonStyle(.borderedProminent)
            .disabled(browse.songs.isEmpty)

            if matchedFollowedArtist != nil {
                Toggle(
                    isOn: Binding(
                        get: { viewModel.library.settings.notifyArtistReleasesOnDevice },
                        set: { enabled in
                            viewModel.updateSettings { $0.notifyArtistReleasesOnDevice = enabled }
                            if enabled {
                                Task {
                                    _ = await ArtistReleaseNotifier.requestAuthorizationIfNeeded()
                                }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notify on new releases")
                            .font(.subheadline.weight(.semibold))
                        Text("Posts a device alert when a followed artist ships a new album. Gotify is configured in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var tabPicker: some View {
        Picker("Section", selection: $selectedTab) {
            Text("Songs").tag(Tab.songs)
            Text("Albums").tag(Tab.albums)
            Text("Playlists").tag(Tab.playlists)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private func albumsBody(_ browse: ArtistBrowseResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if browse.albums.isEmpty {
                Text("No catalog albums.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            ForEach(browse.albums, id: \.id) { album in
                Button {
                    albumTracks = []
                    albumTracksLoading = true
                    expandedAlbum = ExpandedAlbumDraft(album: album)
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: album.artwork ?? "")) { p in
                            if let img = p.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.35)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title).font(.headline).foregroundStyle(.primary)
                            Text(album.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playlistBody(_ browse: ArtistBrowseResult) -> some View {
        Group {
            if browse.playlistsContainingArtist.isEmpty {
                Text("No local playlists containing this artist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            ForEach(browse.playlistsContainingArtist, id: \.id) { pl in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pl.title).font(.headline)
                    Text("\(pl.videos.count) tracks").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let first = pl.videos.first else { return }
                    viewModel.playFromPlaylist(track: first, source: pl.videos)
                }
            }
        }
    }

    private func trackList(_ tracks: [Track]) -> some View {
        Group {
            if tracks.isEmpty {
                Text("No songs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(tracks, id: \.effectiveId) { t in
                    Button {
                        viewModel.play(track: t, source: tracks)
                    } label: {
                        HStack {
                            AsyncImage(url: URL(string: t.artwork ?? "")) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.secondary.opacity(0.35)
                                }
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title).foregroundStyle(.primary).lineLimit(1)
                                Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        let result =
            await viewModel.browseArtistPage(
                artistAppleId: appleArtistId,
                fallbackName: fallbackDisplayName,
            )
        browseResult = result
        loadError =
            result == nil
                ? "Could not resolve this artist via iTunes. Try another spelling."
                : nil
        isLoading = false
    }
}
