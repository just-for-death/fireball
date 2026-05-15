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

private struct RootShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: MainViewModel
    @State private var selectedTab: RootTab = .home
    @State private var isPlayerOpen = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List(RootTab.allCases, selection: $selectedTab) { tab in
                        Label(tab.rawValue.capitalized, systemImage: icon(for: tab))
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let track = viewModel.currentTrack {
                            PillMiniPlayer(
                                track: track,
                                isPlaying: viewModel.isPlaying,
                                progress: viewModel.durationSeconds > 0 ? viewModel.positionSeconds / viewModel.durationSeconds : 0.0,
                                onPlayPause: viewModel.togglePlayPause,
                                onNext: viewModel.next,
                                onTap: { isPlayerOpen = true }
                            )
                            .padding(.bottom, 8)
                        }
                    }
                    .navigationTitle("Fireball")
                } detail: {
                    screen(for: selectedTab)
                        .navigationTitle(selectedTab.rawValue.capitalized)
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
                            onPlayPause: viewModel.togglePlayPause,
                            onNext: viewModel.next,
                            onTap: { isPlayerOpen = true }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 50) // Adjust for tab bar
                    }
                }
            }
        }
        .dynamicTheme(
            artworkUrl: viewModel.currentTrack?.artwork,
            settings: viewModel.library.settings
        )
        .fullScreenCover(isPresented: $isPlayerOpen) {
            if let track = viewModel.currentTrack {
                NowPlayingScreen(
                    track: track,
                    settings: viewModel.library.settings,
                    isPlaying: viewModel.isPlaying,
                    positionSeconds: viewModel.positionSeconds,
                    durationSeconds: viewModel.durationSeconds,
                    currentLyrics: viewModel.currentLyrics,
                    lyricsAutoScroll: viewModel.library.settings.lyricsAutoScroll,
                    lyricsReducedMotion: viewModel.library.settings.lyricsReducedMotion,
                    onPlayPause: viewModel.togglePlayPause,
                    onPrevious: viewModel.previous,
                    onNext: viewModel.next,
                    onSeek: { ratio in
                        let d = viewModel.durationSeconds
                        if d > 0 { viewModel.seekTo(seconds: ratio * d) }
                    },
                    onClose: { isPlayerOpen = false }
                )
            }
        }
        .onAppear {
            if let tab = RootTab(rawValue: viewModel.library.settings.startTab.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                selectedTab = tab
            }
        }
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
                isSearching: viewModel.isSearching,
                error: viewModel.error,
                isFavorite: viewModel.isFavorite,
                onDismissError: { viewModel.clearError() },
                onSearch: viewModel.search,
                onPlay: viewModel.play,
                onFavorite: viewModel.toggleFavorite
            )
        case .library:
            LibraryScreen(
                library: viewModel.library,
                useGrid: viewModel.library.settings.libraryUseGrid,
                isFavorite: viewModel.isFavorite,
                onPlay: viewModel.play,
                onFavorite: viewModel.toggleFavorite
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
