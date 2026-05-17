import SwiftUI

@main
struct FireballNativeApp: App {
    @StateObject private var viewModel: MainViewModel
    private let libraryStore: LibraryStore

    init() {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let store = LibraryStore(baseDirectory: baseDir)
        libraryStore = store
        let repository = FireballRepository(api: FireballAPIClient(), store: store)
        _viewModel = StateObject(wrappedValue: MainViewModel(repository: repository))
        ArtistReleaseBackgroundRefresh.register(store: store)
    }

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(viewModel)
        }
    }
}

private enum RootTab: String, CaseIterable, Identifiable, Hashable {
    case home, search, library, settings
    var id: String { rawValue }
}

private struct OverflowTrackDraft: Identifiable {
    let track: Track
    var id: String { track.effectiveId }
}

private struct RootShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @State private var selectedTab: RootTab = .home
    @State private var isPlayerOpen = false
    @State private var overflowDraft: OverflowTrackDraft?
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    @State private var artistPickerContext: ArtistPickerContext?

    var body: some View {
        PremiumBackground {
            shellRoot
        }
    }

    @ViewBuilder
    private var shellRoot: some View {
        Group {
            if horizontalSizeClass == .regular {
                tabletShell
            } else {
                phoneShell
            }
        }
        .dynamicTheme(
            artworkUrl: viewModel.currentTrack?.artwork,
            settings: viewModel.library.settings
        )
        .onAppear(perform: applyInitialShellState)
        .onChange(of: viewModel.library.settings.startTab) { _, newValue in
            if let tab = RootTab(rawValue: newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                selectedTab = tab
            }
        }
        .onChange(of: viewModel.library.settings.ipadSidebarCollapsed) { _, collapsed in
            splitVisibility = collapsed ? .detailOnly : .doubleColumn
        }
        .sheet(item: $overflowDraft, content: overflowSheet)
        .onChange(of: viewModel.searchFocusRequest) { _, newValue in
            guard let q = newValue, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            selectedTab = .search
            viewModel.query = q
            Task { await viewModel.search() }
            viewModel.consumeSearchFocusRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshFollowedArtistReleaseChecksFromForeground() }
            }
        }
        .onChange(of: viewModel.currentTrack?.effectiveId) { _, trackId in
            if trackId == nil {
                isPlayerOpen = false
            }
        }
        .onChange(of: viewModel.artistOpenRequest) { _, req in
            if req != nil {
                isPlayerOpen = false
            }
        }
        .fullScreenCover(
            item: $viewModel.artistOpenRequest,
            onDismiss: { viewModel.consumeArtistOpenRequest() },
            content: artistCatalogCover
        )
        .sheet(item: $artistPickerContext) { ctx in
            ArtistPickerSheet(context: ctx) { name in
                viewModel.requestArtistDetail(artistDisplayName: name)
                artistPickerContext = nil
            }
        }
    }

    private var tabletShell: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List {
                ForEach(RootTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue.capitalized, systemImage: icon(for: tab))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                miniPlayerInset(chrome: .ipadSidebarRail, horizontalPadding: 10)
            }
            .navigationTitle("Fireball")
        } detail: {
            NavigationStack {
                screen(for: selectedTab)
                    .navigationTitle(selectedTab.rawValue.capitalized)
            }
            .sheet(isPresented: $isPlayerOpen, onDismiss: { isPlayerOpen = false }) {
                if let track = viewModel.currentTrack {
                    fullPlayer(track: track)
                        .modifier(PlayerSheetChrome())
                }
            }
        }
    }

    private var phoneShell: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(tab.rawValue.capitalized)
                }
                .tabItem { Label(tab.rawValue.capitalized, systemImage: icon(for: tab)) }
                .tag(tab)
            }
        }
        .safeAreaInset(edge: .bottom) {
            miniPlayerInset(chrome: .phone, horizontalPadding: 0)
        }
        .fullScreenCover(isPresented: $isPlayerOpen, onDismiss: { isPlayerOpen = false }) {
            if let track = viewModel.currentTrack {
                fullPlayer(track: track)
            }
        }
    }

    @ViewBuilder
    private func miniPlayerInset(chrome: PillMiniPlayerChrome, horizontalPadding: CGFloat) -> some View {
        if let track = viewModel.currentTrack {
            PillMiniPlayer(
                track: track,
                isPlaying: viewModel.isPlaying,
                progress: playbackProgress,
                isLoading: viewModel.isPlaybackLoading,
                onPlayPause: viewModel.togglePlayPause,
                onNext: viewModel.next,
                onPrevious: { viewModel.previous() },
                onTap: { isPlayerOpen = true },
                onLongPressMenu: { overflowDraft = OverflowTrackDraft(track: track) },
                onArtistTap: { handleOpenArtist(track.artist, artwork: track.artwork) },
                onClose: {
                    isPlayerOpen = false
                    viewModel.stopPlaybackAndDismissMiniPlayer()
                },
                chrome: chrome
            )
            .padding(.horizontal, horizontalPadding > 0 ? horizontalPadding : 16)
            .padding(.bottom, 8)
        }
    }

    private var playbackProgress: Double {
        let d = viewModel.durationSeconds
        guard d > 0 else { return 0 }
        return viewModel.positionSeconds / d
    }

    private func applyInitialShellState() {
        if let tab = RootTab(rawValue: viewModel.library.settings.startTab.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            selectedTab = tab
        }
        splitVisibility = viewModel.library.settings.ipadSidebarCollapsed ? .detailOnly : .doubleColumn
        ArtistReleaseBackgroundRefresh.scheduleIfNeeded(settings: viewModel.library.settings)
    }

    @ViewBuilder
    private func overflowSheet(draft: OverflowTrackDraft) -> some View {
        PlayerTrackOverflowSheet(
            track: draft.track,
            onPlayNext: {
                viewModel.playTrackUpNext(track: draft.track)
                overflowDraft = nil
            },
            onAddToQueue: {
                viewModel.appendTrackToQueue(track: draft.track)
                overflowDraft = nil
            },
            onToggleFavorite: {
                viewModel.toggleFavorite(draft.track)
                overflowDraft = nil
            },
            onAddToPlaylist: { pid in
                viewModel.addTrackToPlaylist(track: draft.track, playlistId: pid)
            },
            onSeeArtist: {
                handleOpenArtist(draft.track.artist, artwork: draft.track.artwork)
                overflowDraft = nil
            },
            onFollowArtist: {
                viewModel.followArtist(
                    name: viewModel.primaryArtistName(draft.track.artist),
                    artwork: draft.track.artwork
                )
                overflowDraft = nil
            },
            onUnfollowArtist: {
                viewModel.unfollowFirstFollowedArtistFromDisplayLine(draft.track.artist)
                overflowDraft = nil
            }
        )
    }

    private func artistCatalogCover(req: ArtistOpenRequest) -> some View {
        ArtistCatalogScreen(
            appleArtistId: req.appleId,
            fallbackDisplayName: req.fallbackDisplayName,
            onOverflowTrack: { overflowDraft = OverflowTrackDraft(track: $0) }
        )
        .environmentObject(viewModel)
    }

    private func handleOpenArtist(_ raw: String, artwork: String? = nil) {
        let names = ArtistNameParser.splitArtists(raw)
        switch names.count {
        case 0:
            return
        case 1:
            viewModel.requestArtistDetail(artistDisplayName: names[0])
        default:
            artistPickerContext = ArtistPickerContext(names: names, fallbackArtwork: artwork)
        }
    }

    @ViewBuilder
    private func fullPlayer(track: Track) -> some View {
        NowPlayingScreen(
            track: track,
            settings: viewModel.library.settings,
            isPlaying: viewModel.isPlaying,
            positionSeconds: viewModel.positionSeconds,
            durationSeconds: viewModel.durationSeconds,
            currentLyrics: viewModel.currentLyrics,
            lyricsAutoScroll: viewModel.library.settings.lyricsAutoScroll,
            lyricsReducedMotion: viewModel.library.settings.lyricsReducedMotion,
            shuffled: viewModel.shuffled,
            repeatMode: viewModel.repeatMode,
            onPlayPause: viewModel.togglePlayPause,
            onPrevious: viewModel.previous,
            onNext: viewModel.next,
            onSeek: { ratio in
                let d = viewModel.durationSeconds
                if d > 0 { viewModel.seekTo(seconds: ratio * d) }
            },
            onToggleShuffle: viewModel.toggleShuffle,
            onCycleRepeat: viewModel.cycleRepeat,
            queue: viewModel.queue,
            currentIndex: viewModel.currentIndex,
            onPlayQueueIndex: viewModel.playQueueIndex,
            onOpenArtist: { name, artwork in
                handleOpenArtist(name, artwork: artwork)
            },
            onClose: { isPlayerOpen = false },
            onOpenTrackMenu: {
                if let t = viewModel.currentTrack {
                    overflowDraft = OverflowTrackDraft(track: t)
                }
            },
            onOverflowQueueTrack: { overflowDraft = OverflowTrackDraft(track: $0) },
            onSeekToLyricMs: { ms in
                viewModel.seekTo(seconds: Double(ms) / 1000.0)
            }
        )
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            HomeScreen(
                library: viewModel.library,
                currentTrack: viewModel.currentTrack,
                positionSeconds: viewModel.positionSeconds,
                durationSeconds: viewModel.durationSeconds,
                currentLyrics: viewModel.currentLyrics,
                homeCountries: HomeCountries.visibleCodes(saved: viewModel.library.settings.homeCountries),
                chartCountryCode: viewModel.chartCountryCode,
                trendingTracks: viewModel.trendingTracks,
                trendingLoading: viewModel.trendingLoading,
                onSelectChartCountry: viewModel.selectChartCountry,
                lbRecentTracks: viewModel.lbRecentTracks,
                lbTopTracks: viewModel.lbTopTracks,
                lbTopRange: viewModel.lbTopRange,
                lbHomeLoading: viewModel.lbHomeLoading,
                onSelectLbTopRange: viewModel.selectLbTopRange,
                onFollowArtist: viewModel.followArtist,
                onRefreshHome: { await viewModel.refreshHome() },
                onPlay: viewModel.play,
                onPlayPause: viewModel.togglePlayPause,
                onPrevious: viewModel.previous,
                onNext: viewModel.next,
                isPlaying: viewModel.isPlaying,
                onOverflowTrack: { overflowDraft = OverflowTrackDraft(track: $0) },
                onOpenArtist: { name, artwork in
                    handleOpenArtist(name, artwork: artwork)
                }
            )
        case .search:
            SearchScreen(
                query: $viewModel.query,
                results: viewModel.searchResults,
                albumResults: viewModel.searchAlbumResults,
                searchSuggestions: viewModel.searchSuggestions,
                isSearching: viewModel.isSearching,
                error: viewModel.error,
                isFavorite: viewModel.isFavorite,
                onDismissError: { viewModel.clearError() },
                onSearch: viewModel.search,
                onRefreshSuggestions: { viewModel.refreshSearchSuggestionsNow() },
                onPlay: viewModel.play,
                onPlayAlbum: viewModel.playCatalogAlbum,
                onFavorite: viewModel.toggleFavorite,
                onOverflowTrack: { t in overflowDraft = OverflowTrackDraft(track: t) }
            )
        case .library:
            LibraryScreen(
                library: viewModel.library,
                useGrid: viewModel.library.settings.libraryUseGrid,
                isFavorite: viewModel.isFavorite,
                onPlay: viewModel.play,
                onFavorite: viewModel.toggleFavorite,
                onOverflowTrack: { overflowDraft = OverflowTrackDraft(track: $0) },
                onUnfollowArtist: viewModel.unfollowArtist,
                onOpenArtist: { name, artwork in
                    handleOpenArtist(name, artwork: artwork)
                }
            )
        case .settings:
            SettingsScreen(
                settings: viewModel.library.settings,
                isShuffled: viewModel.shuffled,
                repeatMode: viewModel.repeatMode,
                sleepAfterCurrent: viewModel.sleepAfterCurrent,
                onUpdateSettings: viewModel.updateSettings,
                onToggleShuffle: viewModel.toggleShuffle,
                onCycleRepeat: viewModel.cycleRepeat,
                onSetSleepTimer: viewModel.setSleepTimer,
                onSetSleepAfterCurrent: viewModel.setSleepAfterCurrent,
                onWebDavPull: { Task { await viewModel.webDavPullMerge() } },
                onWebDavPush: { Task { await viewModel.webDavPush() } },
                integrationStatus: viewModel.integrationStatus,
                onGotifyTest: { Task { _ = await viewModel.sendGotifyTest() } },
                onLbdlStatus: { Task { _ = await viewModel.checkLbdl() } },
                onLbdlCreateJob: { Task { _ = await viewModel.createLbdlJobFromQueue() } },
                onRemoteToggle: { Task { _ = await viewModel.sendRemoteCommand("toggle") } },
                onRemotePair: { code in Task { _ = await viewModel.pairRemote(code: code) } },
                invidiousPlaylists: viewModel.invidiousPlaylists,
                onInvidiousLogin: { u, p in viewModel.invidiousLogin(username: u, password: p) },
                onInvidiousRefreshPlaylists: { Task { await viewModel.refreshInvidiousPlaylists() } },
                onInvidiousSyncPlaylist: viewModel.invidiousSyncPlaylist,
                onInvidiousPushPlaylist: viewModel.invidiousPushPlaylist,
                onInvidiousSignOut: viewModel.signOutInvidious,
                onGoogleDriveBackup: { token in
                    Task { _ = await viewModel.backupToGoogleDrive(accessToken: token) }
                },
                onValidateLastFm: { Task { _ = await viewModel.validateLastFmKey() } },
                onConnectLastFm: { password in Task { _ = await viewModel.connectLastFm(password: password) } }
            )
            .task {
                await viewModel.refreshInvidiousPlaylists()
            }
        }
    }

    private func icon(for tab: RootTab) -> String {
        switch tab {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct PlayerSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 16.4, *) {
                content
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            } else if #available(iOS 16.0, *) {
                content.presentationDragIndicator(.visible)
            } else {
                content
            }
        }
    }
}
