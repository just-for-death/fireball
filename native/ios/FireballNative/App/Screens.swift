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
    let onSearch: () async -> Void
    let onPlay: (Track, [Track]) -> Void
    let onFavorite: (Track) -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search music", text: $query)
                .textFieldStyle(.roundedBorder)
            Button(isSearching ? "Searching..." : "Search") {
                Task { await onSearch() }
            }
            .buttonStyle(.borderedProminent)

            List(results, id: \.effectiveId) { track in
                HStack {
                    VStack(alignment: .leading) {
                        Text(track.title)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Play") { onPlay(track, results) }
                    Button("Fav") { onFavorite(track) }
                }
            }
        }
        .padding()
    }
}

struct LibraryScreen: View {
    let library: LibrarySnapshot
    let useGrid: Bool
    let onPlay: (Track, [Track]) -> Void

    var body: some View {
        Group {
            if useGrid {
                ScrollView {
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
                        }
                    }
                    .padding()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playlists: \(library.playlists.count)")
                        Text("Artists followed: \(library.artists.count)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            } else {
                List {
                    Section("Favorites") {
                        ForEach(library.favorites, id: \.effectiveId) { track in
                            Button {
                                onPlay(track, library.favorites)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Library Stats") {
                        Text("Playlists: \(library.playlists.count)")
                        Text("Artists followed: \(library.artists.count)")
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
    @State private var pairCode = ""

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("High Quality Playback", isOn: .init(
                    get: { settings.highQuality },
                    set: { value in onUpdateSettings { $0.highQuality = value } }
                ))
                Toggle("Enable Stream Cache", isOn: .init(
                    get: { settings.cacheEnabled },
                    set: { value in onUpdateSettings { $0.cacheEnabled = value } }
                ))
                TextField("Queue mode", text: .init(
                    get: { settings.queueMode },
                    set: { value in onUpdateSettings { $0.queueMode = value } }
                ))
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
                Toggle("Dynamic Player", isOn: .init(
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
                TextField("Theme mode", text: .init(
                    get: { settings.themeMode },
                    set: { value in onUpdateSettings { $0.themeMode = value } }
                ))
                TextField("Color scheme", text: .init(
                    get: { settings.flexScheme },
                    set: { value in onUpdateSettings { $0.flexScheme = value } }
                ))
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
                TextField("Invidious SID Token (if login fails)", text: .init(
                    get: { settings.invidiousSid ?? "" },
                    set: { value in onUpdateSettings { $0.invidiousSid = value.isEmpty ? nil : value } }
                ))
                TextField("Invidious username", text: .init(
                    get: { settings.invidiousUsername ?? "" },
                    set: { value in onUpdateSettings { $0.invidiousUsername = value.isEmpty ? nil : value } }
                ))
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
                Toggle("Fallback to Piped API", isOn: .init(
                    get: { settings.fallbackToPiped },
                    set: { value in onUpdateSettings { $0.fallbackToPiped = value } }
                ))
                TextField("Piped instance URL", text: .init(
                    get: { settings.pipedInstance },
                    set: { value in onUpdateSettings { $0.pipedInstance = value } }
                ))
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
