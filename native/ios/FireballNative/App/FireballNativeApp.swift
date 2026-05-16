import SwiftUI

@main
struct FireballNativeApp: App {
    @StateObject private var viewModel: MainViewModel

    init() {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let store = LibraryStore(baseDirectory: baseDir)
        let repository = FireballRepository(api: FireballAPIClient(), store: store)
        _viewModel = StateObject(wrappedValue: MainViewModel(repository: repository))
    }

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(viewModel)
        }
    }
}

private enum RootTab: String, CaseIterable, Identifiable {
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

    var body: some View {
        PremiumBackground {
            Group {
                if horizontalSizeClass == .regular {
                    NavigationSplitView(columnVisibility: $splitVisibility) {
                        List(RootTab.allCases, selection: $selectedTab) { tab in
                            Label(tab.rawValue.capitalized, systemImage: icon(for: tab))
                        }
                        .safeAreaInset(edge: .bottom) {
                            if let track = viewModel.currentTrack {
                                PillMiniPlayer(
                                    track: track,
                                    isPlaying: viewModel.isPlaying,
                                    progress: viewModel.durationSeconds > 0 ? viewModel.positionSeconds / viewModel.durationSeconds : 0.0,
                                    isLoading: viewModel.isPlaybackLoading,
                                    onPlayPause: viewModel.togglePlayPause,
                                    onNext: viewModel.next,
                                    onPrevious: { viewModel.previous() },
                                    onTap: { isPlayerOpen = true },
                                    onLongPressMenu: { overflowDraft = OverflowTrackDraft(track: track) },
                                    onArtistTap: { viewModel.requestArtistDetail(artistDisplayName: track.artist) },
                                    onClose: { viewModel.stopPlaybackAndDismissMiniPlayer() },
                                    chrome: .ipadSidebarRail
                                )
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                            }
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
                } else {
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
                        if let track = viewModel.currentTrack {
                            PillMiniPlayer(
                                track: track,
                                isPlaying: viewModel.isPlaying,
                                progress: viewModel.durationSeconds > 0 ? viewModel.positionSeconds / viewModel.durationSeconds : 0.0,
                                isLoading: viewModel.isPlaybackLoading,
                                onPlayPause: viewModel.togglePlayPause,
                                onNext: viewModel.next,
                                onPrevious: {},
                                onTap: { isPlayerOpen = true },
                                onLongPressMenu: { overflowDraft = OverflowTrackDraft(track: track) },
                                onArtistTap: { viewModel.requestArtistDetail(artistDisplayName: track.artist) },
                                onClose: { viewModel.stopPlaybackAndDismissMiniPlayer() },
                                chrome: .phone
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                    }
                    .fullScreenCover(isPresented: $isPlayerOpen, onDismiss: { isPlayerOpen = false }) {
                        if let track = viewModel.currentTrack {
                            fullPlayer(track: track)
                        }
                    }
                }
            }
            .dynamicTheme(
                artworkUrl: viewModel.currentTrack?.artwork,
                settings: viewModel.library.settings
            )
            .onAppear {
                if let tab = RootTab(rawValue: viewModel.library.settings.startTab.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                    selectedTab = tab
                }
                splitVisibility = viewModel.library.settings.ipadSidebarCollapsed ? .detailOnly : .doubleColumn
            }
            .onChange(of: viewModel.library.settings.startTab) { newValue in
                if let tab = RootTab(rawValue: newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                    selectedTab = tab
                }
            }
            .onChange(of: viewModel.library.settings.ipadSidebarCollapsed) { collapsed in
                splitVisibility = collapsed ? .detailOnly : .doubleColumn
            }
            .sheet(item: $overflowDraft) { draft in
                PlayerTrackOverflowSheet(
                    track: draft.track,
                    onPlayNext: {
                        viewModel.playTrackUpNext(draft.track)
                        overflowDraft = nil
                    },
                    onAddToQueue: {
                        viewModel.appendTrackToQueue(draft.track)
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
                        viewModel.requestArtistDetail(artistDisplayName: draft.track.artist)
                        overflowDraft = nil
                    },
                    onFollowArtist: {
                        viewModel.followArtist(draft.track.artist, artwork: draft.track.artwork)
                        overflowDraft = nil
                    }
                )
            }

            .onChange(of: viewModel.searchFocusRequest) { newValue in
                guard let q = newValue, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                selectedTab = .search
                viewModel.query = q
                Task { await viewModel.search() }
                viewModel.consumeSearchFocusRequest()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await viewModel.refreshFollowedArtistReleaseChecksFromForeground() }
                }
            }
            .fullScreenCover(
                item: $viewModel.artistOpenRequest,
                onDismiss: { viewModel.consumeArtistOpenRequest() }
            ) { req in
                ArtistCatalogScreen(appleArtistId: req.appleId, fallbackDisplayName: req.fallbackDisplayName)
                    .environmentObject(viewModel)
            }
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
            onFollowArtist: viewModel.followArtist,
            onClose: { isPlayerOpen = false },
            onOpenTrackMenu: {
                if let t = viewModel.currentTrack {
                    overflowDraft = OverflowTrackDraft(track: t)
                }
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
                isPlaying: viewModel.isPlaying
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
                onUnfollowArtist: viewModel.unfollowArtist
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
