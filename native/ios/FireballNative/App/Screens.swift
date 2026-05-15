import SwiftUI

struct HomeScreen: View {
    let library: LibrarySnapshot
    let currentTrack: Track?
    let positionSeconds: Double
    let durationSeconds: Double
    let currentLyrics: String?
    let onPlay: (Track, [Track]) -> Void
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let isPlaying: Bool

    @Environment(\.dominantColors) var dominantColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recently Played Carousel
                if !library.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(library.history.prefix(20), id: \.effectiveId) { track in
                                    Button {
                                        onPlay(track, library.history)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Rectangle().fill(dominantColors.secondary)
                                                }
                                            }
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            
                                            Text(track.title)
                                                .font(.headline)
                                                .foregroundColor(dominantColors.onBackground)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundColor(dominantColors.onBackground.opacity(0.7))
                                                .lineLimit(1)
                                        }
                                        .frame(width: 140)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if !library.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Playlists")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(library.playlists, id: \.id) { playlist in
                                    Button {
                                        guard let first = playlist.videos.first else { return }
                                        onPlay(first, playlist.videos)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text(playlist.title)
                                                .font(.headline)
                                                .foregroundColor(dominantColors.onBackground)
                                                .lineLimit(2)
                                            Text("\(playlist.videos.count) tracks")
                                                .font(.caption)
                                                .foregroundColor(dominantColors.onBackground.opacity(0.7))
                                        }
                                        .frame(width: 140, alignment: .leading)
                                        .padding(12)
                                        .background(dominantColors.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    .disabled(playlist.videos.isEmpty)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Favorites Carousel
                if !library.favorites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Favorites")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(library.favorites, id: \.effectiveId) { track in
                                    Button {
                                        onPlay(track, library.favorites)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Rectangle().fill(dominantColors.tertiary)
                                                }
                                            }
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            
                                            Text(track.title)
                                                .font(.headline)
                                                .foregroundColor(dominantColors.onBackground)
                                                .lineLimit(1)
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundColor(dominantColors.onBackground.opacity(0.7))
                                                .lineLimit(1)
                                        }
                                        .frame(width: 140)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                Spacer(minLength: 80) // Padding for PillMiniPlayer
            }
            .padding(.top)
        }
        .background(dominantColors.primary.ignoresSafeArea())
    }
}

struct SearchScreen: View {
    @Binding var query: String
    let results: [Track]
    let isSearching: Bool
    let error: String?
    let isFavorite: (Track) -> Bool
    let onDismissError: () -> Void
    let onSearch: () async -> Void
    let onPlay: (Track, [Track]) -> Void
    let onFavorite: (Track) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let error, !error.isEmpty {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { onDismissError() }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
            }
            TextField("Search music", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await onSearch() } }
            Button(isSearching ? "Searching..." : "Search") {
                Task { await onSearch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if results.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No results")
                        .font(.headline)
                    Text("Try another query or check Invidious / network settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, id: \.effectiveId) { track in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Play") { onPlay(track, results) }
                        Button {
                            onFavorite(track)
                        } label: {
                            Image(systemName: isFavorite(track) ? "heart.fill" : "heart")
                                .foregroundStyle(isFavorite(track) ? .red : .secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
    }
}

struct LibraryScreen: View {
    let library: LibrarySnapshot
    let useGrid: Bool
    let isFavorite: (Track) -> Bool
    let onPlay: (Track, [Track]) -> Void
    let onFavorite: (Track) -> Void

    var body: some View {
        Group {
            if useGrid {
                ScrollView {
                    if !library.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Playlists").font(.headline).padding(.horizontal)
                            ForEach(library.playlists, id: \.id) { pl in
                                Button {
                                    guard let first = pl.videos.first else { return }
                                    onPlay(first, pl.videos)
                                } label: {
                                    HStack {
                                        Text(pl.title)
                                        Spacer()
                                        Text("\(pl.videos.count)").foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(pl.videos.isEmpty)
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
                                Button {
                                    guard let first = pl.videos.first else { return }
                                    onPlay(first, pl.videos)
                                } label: {
                                    HStack {
                                        Text(pl.title)
                                        Spacer()
                                        Text("\(pl.videos.count) tracks").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(pl.videos.isEmpty)
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
                }
            }
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
                Toggle("Enable Stream Cache", isOn: .init(
                    get: { settings.cacheEnabled },
                    set: { value in onUpdateSettings { $0.cacheEnabled = value } }
                ))
                Picker("Queue mode", selection: .init(
                    get: { settings.queueMode },
                    set: { value in onUpdateSettings { $0.queueMode = value } }
                )) {
                    Text("Off").tag("off")
                    Text("Continuous").tag("continuous")
                }
                TextField("Local cache limit (GB)", text: .init(
                    get: { "\(settings.localMusicCacheLimit)" },
                    set: { value in if let parsed = Int(value) { onUpdateSettings { $0.localMusicCacheLimit = parsed } } }
                ))
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
                Toggle("Use Dynamic Color", isOn: .init(
                    get: { settings.useDynamicColorWhenAvailable },
                    set: { value in onUpdateSettings { $0.useDynamicColorWhenAvailable = value } }
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
                TextField("Scrobble at % of track", text: .init(
                    get: { "\(settings.listenBrainzScrobblePercent)" },
                    set: { value in
                        if let n = Int(value), (1...100).contains(n) {
                            onUpdateSettings { $0.listenBrainzScrobblePercent = n }
                        }
                    }
                ))
                .keyboardType(.numberPad)
                TextField("Scrobble max seconds", text: .init(
                    get: { "\(settings.listenBrainzScrobbleMaxSeconds)" },
                    set: { value in
                        if let n = Int(value), n > 0 {
                            onUpdateSettings { $0.listenBrainzScrobbleMaxSeconds = n }
                        }
                    }
                ))
                .keyboardType(.numberPad)
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
                Toggle("Remote server enabled", isOn: .init(
                    get: { settings.remoteServerEnabled },
                    set: { value in onUpdateSettings { $0.remoteServerEnabled = value } }
                ))
                TextField("Remote host", text: .init(
                    get: { settings.remoteHostIp },
                    set: { value in onUpdateSettings { $0.remoteHostIp = value } }
                ))
                TextField("Remote port", text: .init(
                    get: { "\(settings.remotePeerPort)" },
                    set: { value in if let parsed = Int(value) { onUpdateSettings { $0.remotePeerPort = parsed } } }
                ))
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
