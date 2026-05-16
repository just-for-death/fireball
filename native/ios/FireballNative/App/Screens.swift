import SwiftUI

struct HomeScreen: View {
    let library: LibrarySnapshot
    let currentTrack: Track?
    let positionSeconds: Double
    let durationSeconds: Double
    let currentLyrics: String?
    var homeCountries: [String] = []
    var chartCountryCode: String = "us"
    var trendingTracks: [Track] = []
    var trendingLoading: Bool = false
    var onSelectChartCountry: (String) -> Void = { _ in }
    var lbRecentTracks: [Track] = []
    var lbTopTracks: [Track] = []
    var lbTopRange: String = "month"
    var lbHomeLoading: Bool = false
    var onSelectLbTopRange: (String) -> Void = { _ in }
    var onFollowArtist: (String, String?) -> Void = { _, _ in }
    var onRefreshHome: () async -> Void = {}
    let onPlay: (Track, [Track]) -> Void
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let isPlaying: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dominantColors) var dominantColors

    private var contentGutter: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private var hourGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5 ... 11: return "Good Morning"
        case 12 ... 16: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    private var dashboardEmpty: Bool {
        library.history.isEmpty && library.favorites.isEmpty && library.playlists.isEmpty &&
            library.albums.isEmpty && trendingTracks.isEmpty &&
            lbRecentTracks.isEmpty && lbTopTracks.isEmpty
    }

    private var listenBrainzReady: Bool {
        let s = library.settings
        let u = s.listenBrainzUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = s.listenBrainzToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.listenBrainzEnabled && !u.isEmpty && !t.isEmpty
    }

    @ViewBuilder
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hourGreeting)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(dominantColors.onBackground)

            if let track = currentTrack {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(dominantColors.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now playing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(dominantColors.onBackground.opacity(0.55))
                        Text("\(track.title) — \(track.artist)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(dominantColors.onBackground)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(dominantColors.onBackground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(dominantColors.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, contentGutter)
        .padding(.bottom, 4)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerBlock

                    if !homeCountries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Charts")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal, contentGutter)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(homeCountries, id: \.self) { code in
                                        let name = HomeCountries.all.first(where: {
                                            $0.code.caseInsensitiveCompare(code) == .orderedSame
                                        })?.name ?? code
                                        let selected = code.caseInsensitiveCompare(chartCountryCode) == .orderedSame
                                        Button {
                                            onSelectChartCountry(code)
                                        } label: {
                                            Text(name)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    selected
                                                        ? dominantColors.primary.opacity(0.35)
                                                        : dominantColors.secondary.opacity(0.5),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, contentGutter)
                            }
                        }
                    }

                    if trendingLoading && trendingTracks.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if !trendingTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trending")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal, contentGutter)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(Array(trendingTracks.enumerated()), id: \.offset) { index, track in
                                        SuvFadeSlideIn.staggered(index: index) {
                                            Button {
                                                onPlay(track, trendingTracks)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                                                        if let image = phase.image {
                                                            image.resizable().aspectRatio(contentMode: .fill)
                                                        } else {
                                                            Rectangle().fill(dominantColors.secondary)
                                                        }
                                                    }
                                                    .frame(width: 140, height: 140)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                    Text(track.title)
                                                        .font(.headline)
                                                        .foregroundStyle(dominantColors.onBackground)
                                                        .lineLimit(1)
                                                    Text(track.artist)
                                                        .font(.caption)
                                                        .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                                                        .lineLimit(1)
                                                }
                                                .frame(width: 140, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, contentGutter)
                            }
                        }
                    }

                    if !lbRecentTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ListenBrainz — Recent")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal, contentGutter)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(lbRecentTracks, id: \.effectiveId) { track in
                                        HomeTrackCard(
                                            track: track,
                                            onPlay: { onPlay(track, lbRecentTracks) },
                                            onFollowArtist: { onFollowArtist(track.artist, track.artwork) }
                                        )
                                    }
                                }
                                .padding(.horizontal, contentGutter)
                            }
                        }
                    }

                    if !lbTopTracks.isEmpty || lbHomeLoading {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ListenBrainz — Top")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal, contentGutter)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(["week", "month", "year", "all_time"], id: \.self) { range in
                                        let label = range == "all_time" ? "All time" : range.capitalized
                                        let selected = lbTopRange.caseInsensitiveCompare(range) == .orderedSame
                                        Button(label) {
                                            onSelectLbTopRange(range)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            selected
                                                ? dominantColors.primary.opacity(0.35)
                                                : dominantColors.secondary.opacity(0.5),
                                            in: Capsule()
                                        )
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, contentGutter)
                            }
                            if lbHomeLoading && lbTopTracks.isEmpty {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(lbTopTracks, id: \.effectiveId) { track in
                                            HomeTrackCard(
                                                track: track,
                                                onPlay: { onPlay(track, lbTopTracks) },
                                                onFollowArtist: { onFollowArtist(track.artist, track.artwork) }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, contentGutter)
                                }
                            }
                        }
                    }

                    if !library.settings.offlineModeEnabled && !listenBrainzReady && !lbHomeLoading &&
                        lbRecentTracks.isEmpty && lbTopTracks.isEmpty {
                        Text("Connect ListenBrainz in Settings to see your recent listens and top tracks.")
                            .font(.subheadline)
                            .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, contentGutter)
                    }

                    if dashboardEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(dominantColors.accent)
                                .padding(28)
                                .background(dominantColors.secondary.opacity(0.45), in: Circle())
                            Text("Welcome to Fireball")
                                .font(.title2.bold())
                                .foregroundStyle(dominantColors.onBackground)
                                .multilineTextAlignment(.center)
                            Text("Your dashboard is empty. Use Search to find music and build your library.")
                                .font(.body)
                                .foregroundStyle(dominantColors.onBackground.opacity(0.74))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 28)
                    }

                    jumpBackSection
                    favoritesSection
                    playlistsSection
                    albumsSection

                    Spacer(minLength: 88)
                }
                .padding(.top, 8)
            }

            quickMixFAB
        }
        .refreshable { await onRefreshHome() }
        .background(dominantColors.primary.ignoresSafeArea())
    }

    @ViewBuilder
    private var jumpBackSection: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Jump Back In")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, contentGutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(library.history.prefix(20)), id: \.effectiveId) { track in
                            Button {
                                onPlay(track, library.history)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                                        if let image = phase.image {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Rectangle().fill(dominantColors.secondary)
                                        }
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Text(track.title)
                                        .font(.headline)
                                        .foregroundStyle(dominantColors.onBackground)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, contentGutter)
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !library.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Favorites")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, contentGutter)
                VStack(spacing: 6) {
                    ForEach(Array(library.favorites.prefix(8)), id: \.effectiveId) { track in
                        Button {
                            onPlay(track, library.favorites)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(dominantColors.tertiary)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(dominantColors.onBackground)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.7))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(dominantColors.onBackground.opacity(0.35))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(dominantColors.secondary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, contentGutter)
            }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        if !library.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Playlists")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, contentGutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(library.playlists, id: \.id) { playlist in
                            Button {
                                guard let first = playlist.videos.first else { return }
                                onPlay(first, playlist.videos)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "music.note.list")
                                        .font(.title3)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.85))
                                    Text(playlist.title)
                                        .font(.headline)
                                        .foregroundStyle(dominantColors.onBackground)
                                        .lineLimit(2)
                                    Text("\(playlist.videos.count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                                }
                                .frame(width: 160, alignment: .leading)
                                .padding(14)
                                .background(dominantColors.secondary.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(playlist.videos.isEmpty)
                        }
                    }
                    .padding(.horizontal, contentGutter)
                }
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        if !library.albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Albums")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, contentGutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(library.albums, id: \.id) { album in
                            Button {
                                guard let tracks = album.tracks, let first = tracks.first else { return }
                                onPlay(first, tracks)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(dominantColors.secondary.opacity(0.55))
                                        if let art = album.artwork, let u = URL(string: art), !art.isEmpty {
                                            AsyncImage(url: u) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Image(systemName: "square.stack")
                                                        .font(.title)
                                                        .foregroundStyle(dominantColors.onBackground.opacity(0.45))
                                                }
                                            }
                                        } else {
                                            Image(systemName: "square.stack")
                                                .font(.title)
                                                .foregroundStyle(dominantColors.onBackground.opacity(0.45))
                                        }
                                    }
                                    .frame(width: 130, height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Text(album.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(dominantColors.onBackground)
                                        .lineLimit(1)
                                    Text(album.artist)
                                        .font(.caption)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                                        .lineLimit(1)
                                }
                                .frame(width: 130, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(album.tracks?.isEmpty != false)
                        }
                    }
                    .padding(.horizontal, contentGutter)
                }
            }
        }
    }

    @ViewBuilder
    private var quickMixFAB: some View {
        if !library.history.isEmpty {
            Button {
                if let pick = library.history.randomElement() {
                    onPlay(pick, library.history)
                }
            } label: {
                Label("Quick Mix", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(dominantColors.accent, in: Capsule())
                    .foregroundStyle(Color.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 92)
            .accessibilityHint("Shuffle play from listening history.")
        }
    }
}

private struct HomeTrackCard: View {
    let track: Track
    let onPlay: () -> Void
    let onFollowArtist: () -> Void
    @Environment(\.dominantColors) var dominantColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                VStack(alignment: .leading, spacing: 8) {
                    AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(dominantColors.secondary)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(dominantColors.onBackground)
                        .lineLimit(1)
                }
                .frame(width: 140, alignment: .leading)
            }
            .buttonStyle(.plain)
            Text(track.artist)
                .font(.caption)
                .foregroundStyle(dominantColors.onBackground.opacity(0.72))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onFollowArtist() }
                .accessibilityLabel("Follow \(track.artist)")
        }
        .frame(width: 140, alignment: .leading)
    }
}
struct SearchScreen: View {
    enum SearchSegment: Hashable {
        case songs
        case albums
    }

    @Binding var query: String
    let results: [Track]
    let albumResults: [Album]
    let searchSuggestions: [Track]
    let isSearching: Bool
    let error: String?
    let isFavorite: (Track) -> Bool
    let onDismissError: () -> Void
    let onSearch: () async -> Void
    let onRefreshSuggestions: () -> Void
    let onPlay: (Track, [Track]) -> Void
    let onPlayAlbum: (Album) -> Void
    let onFavorite: (Track) -> Void
    let onOverflowTrack: (Track) -> Void

    @State private var segment: SearchSegment = .songs

    var body: some View {
        VStack(spacing: 12) {
            if let error, !error.isEmpty {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { onDismissError() }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
            }

            TextField("Search music", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await onSearch() } }
                .onAppear { onRefreshSuggestions() }

            Button(isSearching ? "Searching..." : "Search") {
                Task { await onSearch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
                !searchSuggestions.isEmpty &&
                segment == .songs &&
                results.isEmpty &&
                !isSearching {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(searchSuggestions, id: \.effectiveId) { t in
                                Button {
                                    query = t.title
                                    Task { await onSearch() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title)
                                            Text(t.artist).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Track actions…") {
                                        onOverflowTrack(t)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .padding(.horizontal, 4)
            }

            Picker("", selection: $segment) {
                Text("Songs").tag(SearchSegment.songs)
                Text("Albums").tag(SearchSegment.albums)
            }
            .pickerStyle(.segmented)

            Group {
                switch segment {
                case .songs:
                    songsBody
                case .albums:
                    albumsBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    @ViewBuilder
    private var songsBody: some View {
        if results.isEmpty && !isSearching {
            emptyState(icon: "magnifyingglass", title: "No song results yet", subtitle: "Run search or tap a suggestion.")
        } else {
            List(results, id: \.effectiveId) { track in
                Button {
                    onPlay(track, results)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            onFavorite(track)
                        } label: {
                            Image(systemName: isFavorite(track) ? "heart.fill" : "heart")
                                .foregroundStyle(isFavorite(track) ? .red : .secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Track actions…") {
                        onOverflowTrack(track)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var albumsBody: some View {
        if albumResults.isEmpty && !isSearching {
            emptyState(icon: "opticaldisc", title: "No albums", subtitle: "Switch to Songs or refine your query.")
        } else {
            List(albumResults, id: \.id) { album in
                Button {
                    onPlayAlbum(album)
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: album.artwork ?? "")) { p in
                            if let img = p.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.35)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                            Text(album.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct PlaylistDetailScreen: View {
    let playlist: Playlist
    @EnvironmentObject private var viewModel: MainViewModel

    private var playableSource: [Track] {
        playlist.videos
    }

    var body: some View {
        Group {
            if playableSource.isEmpty {
                Text("This playlist has no tracks yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playableSource, id: \.effectiveId) { track in
                    Button {
                        viewModel.playFromPlaylist(track: track, source: playableSource)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !playableSource.isEmpty, let first = playableSource.first {
                    Button("Play") {
                        viewModel.play(track: first, source: playableSource)
                    }
                    Button("Next") {
                        viewModel.appendTracksUpNext(playableSource)
                    }
                    Button("Queue") {
                        viewModel.appendTracksToQueue(playableSource)
                    }
                }
            }
        }
    }
}

struct LibraryScreen: View {
    let library: LibrarySnapshot
    let useGrid: Bool
    let isFavorite: (Track) -> Bool
    let onPlay: (Track, [Track]) -> Void
    let onFavorite: (Track) -> Void
    var onUnfollowArtist: (String) -> Void = { _ in }

    @EnvironmentObject private var viewModel: MainViewModel
    @State private var newPlaylistTitle = ""
    @State private var showCreatePlaylistPrompt = false
    @State private var followArtistName = ""
    @State private var showFollowArtistPrompt = false

    var body: some View {
        Group {
            if useGrid {
                ScrollView {
                    if !library.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Playlists").font(.headline).padding(.horizontal)
                            ForEach(library.playlists, id: \.id) { pl in
                                NavigationLink(destination: PlaylistDetailScreen(playlist: pl)) {
                                    HStack {
                                        Text(pl.title)
                                        Spacer()
                                        Text("\(pl.videos.count)").foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    if !library.history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("History").font(.headline).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(library.history.prefix(20), id: \.effectiveId) { track in
                                        Button {
                                            onPlay(track, library.history)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(track.title).lineLimit(1)
                                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            .frame(width: 140, alignment: .leading)
                                            .padding(10)
                                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    if !library.artists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Followed artists").font(.headline).padding(.horizontal)
                            ForEach(library.artists, id: \.artistId) { artist in
                                HStack {
                                    Text(artist.name).lineLimit(1)
                                    Spacer()
                                    Button("Unfollow") { onUnfollowArtist(artist.artistId) }
                                        .font(.caption)
                                }
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(library.favorites, id: \.effectiveId) { track in
                            Button {
                                onPlay(track, library.favorites)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).lineLimit(2)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .contextMenu {
                                Button(isFavorite(track) ? "Remove favorite" : "Add favorite") {
                                    onFavorite(track)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    if !library.playlists.isEmpty {
                        Section("Playlists") {
                            ForEach(library.playlists, id: \.id) { pl in
                                NavigationLink(destination: PlaylistDetailScreen(playlist: pl)) {
                                    HStack {
                                        Text(pl.title)
                                        Spacer()
                                        Text("\(pl.videos.count) tracks").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section("Favorites") {
                        if library.favorites.isEmpty {
                            Text("No favorites yet — use Search or the heart button while playing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(library.favorites, id: \.effectiveId) { track in
                            HStack {
                                Button {
                                    onPlay(track, library.favorites)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    onFavorite(track)
                                } label: {
                                    Image(systemName: "heart.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    if !library.history.isEmpty {
                        Section("History") {
                            ForEach(library.history.prefix(30), id: \.effectiveId) { track in
                                Button {
                                    onPlay(track, library.history)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !library.artists.isEmpty {
                        Section("Followed artists") {
                            ForEach(library.artists, id: \.artistId) { artist in
                                HStack {
                                    Text(artist.name)
                                    Spacer()
                                    Button("Unfollow") { onUnfollowArtist(artist.artistId) }
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    followArtistName = ""
                    showFollowArtistPrompt = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Follow artist")
                Button {
                    newPlaylistTitle = ""
                    showCreatePlaylistPrompt = true
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .accessibilityLabel("New playlist")
            }
        }
        .alert("Follow artist", isPresented: $showFollowArtistPrompt) {
            TextField("Artist name", text: $followArtistName)
            Button("Follow") {
                viewModel.followArtist(followArtistName.trimmingCharacters(in: .whitespacesAndNewlines), artwork: nil)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New playlist", isPresented: $showCreatePlaylistPrompt) {
            TextField("Title", text: $newPlaylistTitle)
            Button("Create") {
                viewModel.createPlaylist(title: newPlaylistTitle)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SettingsScreen: View {
    let settings: FireballSettings
    let isShuffled: Bool
    let repeatMode: RepeatMode
    let sleepAfterCurrent: Bool
    let onUpdateSettings: ((inout FireballSettings) -> Void) -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    let onSetSleepTimer: (Int?) -> Void
    let onSetSleepAfterCurrent: (Bool) -> Void
    let onWebDavPull: () -> Void
    let onWebDavPush: () -> Void
    let integrationStatus: String?
    let onGotifyTest: () -> Void
    let onLbdlStatus: () -> Void
    let onLbdlCreateJob: () -> Void
    let onRemoteToggle: () -> Void
    let onRemotePair: (String) -> Void
    let invidiousPlaylists: [(id: String, title: String)]
    let onInvidiousLogin: (String, String) -> Void
    let onInvidiousRefreshPlaylists: () -> Void
    let onInvidiousSyncPlaylist: (String) -> Void
    let onInvidiousPushPlaylist: (String, String?) -> Void
    let onGoogleDriveBackup: (String) -> Void
    let onValidateLastFm: () -> Void
    let onConnectLastFm: (String) -> Void

    @State private var pairCode = ""
    @State private var invidiousPassword = ""
    @State private var lastFmPassword = ""
    @State private var pushLocalPlaylistId = ""
    @State private var pushRemotePlaylistId = ""
    @State private var gDriveAccessToken = ""

    var body: some View {
        Form {
            if let integrationStatus, !integrationStatus.isEmpty {
                Section("Status") {
                    Text(integrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Playback") {
                Toggle("High Quality Playback", isOn: .init(
                    get: { settings.highQuality },
                    set: { value in onUpdateSettings { $0.highQuality = value } }
                ))
                Toggle("Cache search results", isOn: .init(
                    get: { settings.cacheEnabled },
                    set: { value in onUpdateSettings { $0.cacheEnabled = value } }
                ))
                TextField("Search cache max entries (0 = auto)", text: .init(
                    get: { settings.searchCacheMaxEntries > 0 ? "\(settings.searchCacheMaxEntries)" : "" },
                    set: { value in
                        let n = Int(value) ?? 0
                        onUpdateSettings { $0.searchCacheMaxEntries = n }
                    }
                ))
                .keyboardType(.numberPad)
                Toggle("Cache streams on disk", isOn: .init(
                    get: { settings.streamCacheEnabled },
                    set: { value in onUpdateSettings { $0.streamCacheEnabled = value } }
                ))
                Text("Caches HTTP streams under the app cache directory (size follows GB limit below).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Queue mode at end", selection: .init(
                    get: { settings.queueMode },
                    set: { value in onUpdateSettings { $0.queueMode = value } }
                )) {
                    Text("Off").tag("off")
                    Text("Repeat queue").tag("repeat")
                    Text("AI append").tag("ai")
                }
                TextField("Stream disk cache size GB", text: .init(
                    get: { "\(settings.localMusicCacheLimit)" },
                    set: { value in if let parsed = Int(value) { onUpdateSettings { $0.localMusicCacheLimit = parsed } } }
                ))
                .keyboardType(.numberPad)
            }
            Section("General") {
                Toggle("Offline Mode", isOn: .init(
                    get: { settings.offlineModeEnabled },
                    set: { value in onUpdateSettings { $0.offlineModeEnabled = value } }
                ))
                Toggle("Privacy Mode", isOn: .init(
                    get: { settings.privacyModeEnabled },
                    set: { value in onUpdateSettings { $0.privacyModeEnabled = value } }
                ))
                Toggle("Live Activity / Dynamic Island", isOn: .init(
                    get: { settings.dynamicIslandEnabled },
                    set: { value in onUpdateSettings { $0.dynamicIslandEnabled = value } }
                ))
                Toggle("Crash Reporting & Logging", isOn: .init(
                    get: { settings.loggingEnabled },
                    set: { value in onUpdateSettings { $0.loggingEnabled = value } }
                ))
                Toggle("Bluetooth Autoplay", isOn: .init(
                    get: { settings.bluetoothAutoplayEnabled },
                    set: { value in onUpdateSettings { $0.bluetoothAutoplayEnabled = value } }
                ))
                Toggle("Announce Songs (TTS)", isOn: .init(
                    get: { settings.speakSongDetailsEnabled },
                    set: { value in onUpdateSettings { $0.speakSongDetailsEnabled = value } }
                ))
                Toggle("Collapse iPad sidebar", isOn: .init(
                    get: { settings.ipadSidebarCollapsed },
                    set: { value in onUpdateSettings { $0.ipadSidebarCollapsed = value } }
                ))
                Text("Home chart regions")
                    .font(.headline)
                ForEach(HomeCountries.all, id: \.code) { entry in
                    let selected = settings.homeCountries.contains(entry.code)
                    Toggle(entry.name, isOn: .init(
                        get: { selected },
                        set: { on in
                            var codes = Set(settings.homeCountries)
                            if on { codes.insert(entry.code) } else { codes.remove(entry.code) }
                            onUpdateSettings { $0.homeCountries = Array(codes).sorted() }
                        }
                    ))
                }
            }
            Section("Appearance") {
                Picker("Theme mode", selection: .init(
                    get: { settings.themeMode },
                    set: { value in onUpdateSettings { $0.themeMode = value } }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Color scheme", selection: .init(
                    get: { settings.flexScheme },
                    set: { value in onUpdateSettings { $0.flexScheme = value } }
                )) {
                    Text("Deep purple").tag("deepPurple")
                    Text("Ocean").tag("ocean")
                    Text("Sunset").tag("sunset")
                    Text("Nature").tag("nature")
                    Text("Love").tag("mandyRed")
                }
                Picker("Chrome colors", selection: .init(
                    get: {
                        let raw = settings.appearanceColorSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if raw == "scheme" || raw == "material_you" { return "scheme" }
                        if raw == "music" { return "music" }
                        return settings.useDynamicColorWhenAvailable ? "music" : "scheme"
                    },
                    set: { v in
                        onUpdateSettings { s in
                            s.appearanceColorSource = v
                            s.useDynamicColorWhenAvailable = (v == "music")
                        }
                    },
                )) {
                    Text("Album artwork").tag("music")
                    Text("Preset scheme").tag("scheme")
                }
                Text("Synced as `appearanceColorSource` (`music` \| `scheme`). Android’s Material You maps to preset scheme here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Accent seed (ARGB hex)", text: .init(
                    get: {
                        guard let seed = settings.accentSeedColor else { return "" }
                        return String(format: "%08X", UInt32(bitPattern: seed))
                    },
                    set: { raw in
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "0x", with: "")
                            .replacingOccurrences(of: "#", with: "")
                        if trimmed.isEmpty {
                            onUpdateSettings { $0.accentSeedColor = nil }
                        } else if let value = UInt32(trimmed, radix: 16) {
                            onUpdateSettings { $0.accentSeedColor = Int32(bitPattern: value) }
                        }
                    }
                ))
                Toggle("Auto-scroll lyrics", isOn: .init(
                    get: { settings.lyricsAutoScroll },
                    set: { value in onUpdateSettings { $0.lyricsAutoScroll = value } }
                ))
                Toggle("Reduce lyrics motion", isOn: .init(
                    get: { settings.lyricsReducedMotion },
                    set: { value in onUpdateSettings { $0.lyricsReducedMotion = value } }
                ))
                Toggle("Prefer English/Hindi lyrics", isOn: .init(
                    get: { settings.lyricsPreferEnglishHindi },
                    set: { value in onUpdateSettings { $0.lyricsPreferEnglishHindi = value } }
                ))
                Toggle("Always show lyrics panel", isOn: .init(
                    get: { settings.alwaysShowLyricsPanel },
                    set: { value in onUpdateSettings { $0.alwaysShowLyricsPanel = value } }
                ))
                TextField("Start tab", text: .init(
                    get: { settings.startTab },
                    set: { value in onUpdateSettings { $0.startTab = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
                ))
                Toggle("Library Grid Layout", isOn: .init(
                    get: { settings.libraryUseGrid },
                    set: { value in onUpdateSettings { $0.libraryUseGrid = value } }
                ))
            }
            Section("Integrations") {
                Toggle("Enable SponsorBlock", isOn: .init(
                    get: { settings.sponsorBlock },
                    set: { value in onUpdateSettings { $0.sponsorBlock = value } }
                ))
                TextField("SponsorBlock categories (csv)", text: .init(
                    get: { settings.sponsorBlockCategories.joined(separator: ",") },
                    set: { value in
                        let categories = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        onUpdateSettings { $0.sponsorBlockCategories = categories }
                    }
                ))
                TextField("Invidious instance URL", text: .init(
                    get: { settings.invidiousInstance },
                    set: { value in onUpdateSettings { $0.invidiousInstance = value } }
                ))
                TextField("Invidious username", text: .init(
                    get: { settings.invidiousUsername ?? "" },
                    set: { value in onUpdateSettings { $0.invidiousUsername = value.isEmpty ? nil : value } }
                ))
                SecureField("Invidious password", text: $invidiousPassword)
                Button("Log in to Invidious") {
                    onInvidiousLogin(settings.invidiousUsername ?? "", invidiousPassword)
                    invidiousPassword = ""
                }
                .disabled(settings.invidiousInstance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if settings.invidiousSid != nil, !(settings.invidiousSid ?? "").isEmpty {
                    Label("Signed in (SID stored)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh my Invidious playlists") { onInvidiousRefreshPlaylists() }
                }
                if !invidiousPlaylists.isEmpty {
                    ForEach(invidiousPlaylists, id: \.id) { pl in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pl.title).lineLimit(1)
                                Text(pl.id).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                            Button("Sync") { onInvidiousSyncPlaylist(pl.id) }
                        }
                    }
                }
                TextField("Invidious playlist privacy", text: .init(
                    get: { settings.invidiousPlaylistPrivacy },
                    set: { value in onUpdateSettings { $0.invidiousPlaylistPrivacy = value } }
                ))
                Toggle("Invidious auto-push", isOn: .init(
                    get: { settings.invidiousAutoPush },
                    set: { value in onUpdateSettings { $0.invidiousAutoPush = value } }
                ))
                TextField("Invidious favorites playlist ID", text: .init(
                    get: { settings.invidiousPlaylistMappings["favorites"] ?? "" },
                    set: { value in
                        onUpdateSettings { s in
                            var map = s.invidiousPlaylistMappings
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty { map.removeValue(forKey: "favorites") }
                            else { map["favorites"] = trimmed }
                            s.invidiousPlaylistMappings = map
                        }
                    }
                ))
                TextField("Invidious playlist mappings (localId:remoteId,csv)", text: .init(
                    get: { settings.invidiousPlaylistMappings.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",") },
                    set: { value in
                        let pairs = value.split(separator: ",")
                            .map { $0.split(separator: ":", maxSplits: 1).map(String.init) }
                            .filter { $0.count == 2 }
                        var dict: [String: String] = [:]
                        pairs.forEach { dict[$0[0].trimmingCharacters(in: .whitespaces)] = $0[1].trimmingCharacters(in: .whitespaces) }
                        onUpdateSettings { $0.invidiousPlaylistMappings = dict }
                    }
                ))
                TextField("Local playlist id to push", text: $pushLocalPlaylistId)
                TextField("Existing Invidious playlist id (optional)", text: $pushRemotePlaylistId)
                Button("Push playlist to Invidious") {
                    let remote = pushRemotePlaylistId.trimmingCharacters(in: .whitespacesAndNewlines)
                    onInvidiousPushPlaylist(
                        pushLocalPlaylistId.trimmingCharacters(in: .whitespacesAndNewlines),
                        remote.isEmpty ? nil : remote
                    )
                }
                .disabled(pushLocalPlaylistId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                DisclosureGroup("Advanced: Invidious SID") {
                    TextField("Manual SID (optional)", text: .init(
                        get: { settings.invidiousSid ?? "" },
                        set: { value in onUpdateSettings { $0.invidiousSid = value.isEmpty ? nil : value } }
                    ))
                }
                Text("Playback resolves via your Invidious instance (optional), public mirrors, then on-device YouTube extraction when Invidious is unavailable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("ListenBrainz enabled", isOn: .init(
                    get: { settings.listenBrainzEnabled },
                    set: { value in onUpdateSettings { $0.listenBrainzEnabled = value } }
                ))
                Toggle("ListenBrainz now-playing", isOn: .init(
                    get: { settings.listenBrainzPlayingNow },
                    set: { value in onUpdateSettings { $0.listenBrainzPlayingNow = value } }
                ))
                TextField("ListenBrainz token", text: .init(
                    get: { settings.listenBrainzToken },
                    set: { value in onUpdateSettings { $0.listenBrainzToken = value } }
                ))
                TextField("ListenBrainz username", text: .init(
                    get: { settings.listenBrainzUsername },
                    set: { value in onUpdateSettings { $0.listenBrainzUsername = value } }
                ))
                Toggle("Enable scrobbling", isOn: .init(
                    get: { settings.scrobbleEnabled },
                    set: { value in onUpdateSettings { $0.scrobbleEnabled = value } }
                ))
                Text(
                    "Scrobble when either threshold is reached first. Tracks shorter than \(settings.listenBrainzScrobbleMinTrackSeconds)s are skipped."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text("At \(settings.listenBrainzScrobblePercent)% of track")
                Slider(
                    value: Binding(
                        get: { Double(min(95, max(5, settings.listenBrainzScrobblePercent))) },
                        set: { v in onUpdateSettings { $0.listenBrainzScrobblePercent = Int(v.rounded()) } }
                    ),
                    in: 5...95,
                    step: 1
                )
                Text("Or after \(settings.listenBrainzScrobbleMaxSeconds)s")
                Slider(
                    value: Binding(
                        get: { Double(min(240, max(10, settings.listenBrainzScrobbleMaxSeconds))) },
                        set: { v in onUpdateSettings { $0.listenBrainzScrobbleMaxSeconds = Int(v.rounded()) } }
                    ),
                    in: 10...240,
                    step: 1
                )
                Text("Minimum track length: \(settings.listenBrainzScrobbleMinTrackSeconds)s")
                Slider(
                    value: Binding(
                        get: { Double(min(120, max(15, settings.listenBrainzScrobbleMinTrackSeconds))) },
                        set: { v in onUpdateSettings { $0.listenBrainzScrobbleMinTrackSeconds = Int(v.rounded()) } }
                    ),
                    in: 15...120,
                    step: 1
                )
                Toggle("Analytics events", isOn: .init(
                    get: { settings.analytics },
                    set: { value in onUpdateSettings { $0.analytics = value } }
                ))
                TextField("Last.fm API key", text: .init(
                    get: { settings.lastFmApiKey },
                    set: { value in onUpdateSettings { $0.lastFmApiKey = value } }
                ))
                TextField("Last.fm shared secret", text: .init(
                    get: { settings.lastFmApiSecret },
                    set: { value in onUpdateSettings { $0.lastFmApiSecret = value } }
                ))
                TextField("Last.fm username", text: .init(
                    get: { settings.lastFmUsername },
                    set: { value in onUpdateSettings { $0.lastFmUsername = value } }
                ))
                SecureField("Last.fm password (not saved)", text: $lastFmPassword)
                HStack {
                    Button("Validate key") { onValidateLastFm() }
                    Button("Connect") { onConnectLastFm(lastFmPassword) }
                }
                if !settings.lastFmSessionKey.isEmpty {
                    Text("Last.fm session active").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Enable AI queue", isOn: .init(
                    get: { settings.ollamaEnabled },
                    set: { value in onUpdateSettings { $0.ollamaEnabled = value } }
                ))
                TextField("Ollama URL", text: .init(
                    get: { settings.ollamaUrl },
                    set: { value in onUpdateSettings { $0.ollamaUrl = value } }
                ))
                TextField("Ollama model", text: .init(
                    get: { settings.ollamaModel },
                    set: { value in onUpdateSettings { $0.ollamaModel = value } }
                ))
            }
            Section("Sync & Backup") {
                Toggle("WebDAV live sync", isOn: .init(
                    get: { settings.webDavLiveSync },
                    set: { value in onUpdateSettings { $0.webDavLiveSync = value } }
                ))
                TextField("WebDAV URL", text: .init(
                    get: { settings.webDavUrl },
                    set: { value in onUpdateSettings { $0.webDavUrl = value } }
                ))
                TextField("WebDAV username", text: .init(
                    get: { settings.webDavUsername },
                    set: { value in onUpdateSettings { $0.webDavUsername = value } }
                ))
                TextField("WebDAV password", text: .init(
                    get: { settings.webDavPassword },
                    set: { value in onUpdateSettings { $0.webDavPassword = value } }
                ))
                Toggle("Google Drive backup", isOn: .init(
                    get: { settings.gDriveEnabled },
                    set: { value in onUpdateSettings { $0.gDriveEnabled = value } }
                ))
                if let last = settings.lastBackupAt, !last.isEmpty {
                    Text("Last backup: \(last)").font(.caption).foregroundStyle(.secondary)
                }
                SecureField("Google Drive access token", text: $gDriveAccessToken)
                Button("Backup library to Google Drive") {
                    onGoogleDriveBackup(gDriveAccessToken)
                    gDriveAccessToken = ""
                }
                .disabled(!settings.gDriveEnabled || gDriveAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                TextField("Custom download folder path", text: .init(
                    get: { settings.customDownloadPath ?? "" },
                    set: { value in
                        onUpdateSettings { $0.customDownloadPath = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
                    }
                ))
            }
            Section("Playback Behavior") {
                Text("Repeat: \(repeatMode.rawValue.capitalized)")
                Button(isShuffled ? "Unshuffle" : "Shuffle", action: onToggleShuffle)
                Button("Cycle Repeat", action: onCycleRepeat)
                Button("Sleep 15m") { onSetSleepTimer(15) }
                Button("Clear Sleep") { onSetSleepTimer(nil) }
                Toggle("Sleep after current track", isOn: .init(
                    get: { sleepAfterCurrent },
                    set: onSetSleepAfterCurrent
                ))
            }
            Section("WebDAV") {
                Button("WebDAV Pull", action: onWebDavPull)
                Button("WebDAV Push", action: onWebDavPush)
            }
            Section("Remote, Notifications, LBDL") {
                Toggle("Remote control (client)", isOn: .init(
                    get: { settings.remoteServerEnabled },
                    set: { value in onUpdateSettings { $0.remoteServerEnabled = value } }
                ))
                Text("Sends commands to another Fireball device on the LAN. iOS does not host an inbound server (unlike Flutter desktop).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Remote host", text: .init(
                    get: { settings.remoteHostIp },
                    set: { value in onUpdateSettings { $0.remoteHostIp = value } }
                ))
                TextField("Remote port", text: .init(
                    get: { "\(settings.remotePeerPort)" },
                    set: { value in if let parsed = Int(value) { onUpdateSettings { $0.remotePeerPort = parsed } } }
                ))
                Toggle("Artist release alerts (this device)", isOn: .init(
                    get: { settings.notifyArtistReleasesOnDevice },
                    set: { value in onUpdateSettings { $0.notifyArtistReleasesOnDevice = value } }
                ))
                Text("Posts a local notification when a followed artist’s newest iTunes album changes; works alongside Gotify when configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Gotify enabled", isOn: .init(
                    get: { settings.gotifyEnabled },
                    set: { value in onUpdateSettings { $0.gotifyEnabled = value } }
                ))
                TextField("Gotify URL", text: .init(
                    get: { settings.gotifyUrl },
                    set: { value in onUpdateSettings { $0.gotifyUrl = value } }
                ))
                TextField("Gotify token", text: .init(
                    get: { settings.gotifyToken },
                    set: { value in onUpdateSettings { $0.gotifyToken = value } }
                ))
                TextField("LBDL URL", text: .init(
                    get: { settings.lbdlUrl },
                    set: { value in onUpdateSettings { $0.lbdlUrl = value } }
                ))
                TextField("LBDL username", text: .init(
                    get: { settings.lbdlUsername },
                    set: { value in onUpdateSettings { $0.lbdlUsername = value } }
                ))
                TextField("LBDL password", text: .init(
                    get: { settings.lbdlPassword },
                    set: { value in onUpdateSettings { $0.lbdlPassword = value } }
                ))
                Button("Gotify Test", action: onGotifyTest)
                Button("LBDL Status", action: onLbdlStatus)
                Button("LBDL Queue Job", action: onLbdlCreateJob)
                Button("Remote Toggle", action: onRemoteToggle)
                TextField("Remote Pair Code", text: $pairCode)
                Button("Pair Remote") { onRemotePair(pairCode) }
                if let integrationStatus, !integrationStatus.isEmpty {
                    Text(integrationStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
