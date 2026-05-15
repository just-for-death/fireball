import Foundation

struct Track: Codable, Hashable {
    let id: String
    let videoId: String?
    let title: String
    let artist: String
    let artwork: String?
    let url: String?
    let duration: Int?
    let album: String?
    let year: String?

    var effectiveId: String { videoId ?? id }
}

struct Playlist: Codable, Hashable {
    let id: String
    let title: String
    let videos: [Track]
}

struct Artist: Codable, Hashable {
    let artistId: String
    let name: String
    let artwork: String?
    let latestReleaseId: String?
}

struct Album: Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artwork: String?
    let year: Int?
    let tracks: [Track]?
}

struct FireballSettings: Codable, Hashable {
    var ollamaEnabled = false
    var ollamaUrl = ""
    var ollamaModel = "llama3.2:3b"
    var lastFmApiKey = ""
    var listenBrainzToken = ""
    var listenBrainzUsername = ""
    var highQuality = false
    var cacheEnabled = true
    var localMusicCacheLimit = 10
    var queueMode = "off"
    var invidiousInstance = ""
    var invidiousSid: String?
    var invidiousUsername: String?
    var sponsorBlock = false
    var sponsorBlockCategories: [String] = []
    var analytics = false
    var customDownloadPath: String?
    var listenBrainzEnabled = false
    var listenBrainzPlayingNow = false
    var listenBrainzScrobblePercent = 25
    var listenBrainzScrobbleMaxSeconds = 40
    var invidiousPlaylistPrivacy = "private"
    var invidiousAutoPush = false
    var invidiousPlaylistMappings: [String: String] = [:]
    var webDavUrl = ""
    var webDavUsername = ""
    var webDavPassword = ""
    var gDriveEnabled = false
    var lastBackupAt: String?
    var webDavLiveSync = false
    var remoteServerEnabled = false
    var remoteHostIp = ""
    var remotePeerPort = 7771
    var homeCountries: [String] = []
    var lyricsAutoScroll = true
    var lyricsReducedMotion = false
    var lyricsPreferEnglishHindi = true
    var themeMode = "system"
    var flexScheme = "deepPurple"
    var useDynamicColorWhenAvailable = true
    var accentSeedColor: Int?
    var ipadSidebarCollapsed = false
    var gotifyEnabled = false
    var gotifyUrl = ""
    var gotifyToken = ""
    var lbdlUrl = ""
    var lbdlUsername = ""
    var lbdlPassword = ""
    var offlineModeEnabled = false
    var privacyModeEnabled = false
    var dynamicIslandEnabled = false
    var loggingEnabled = false
    var bluetoothAutoplayEnabled = false
    var speakSongDetailsEnabled = false
    var startTab = "home"
    var libraryUseGrid = false
}

/// Restored on launch so queue / shuffle / repeat survive app restarts.
struct PlaybackSession: Codable, Hashable {
    var queue: [Track] = []
    var currentIndex: Int = 0
    var shuffled: Bool = false
    var repeatMode: String = "off"
}

struct LibrarySnapshot: Codable, Hashable {
    var version = 2
    var settings = FireballSettings()
    var history: [Track] = []
    var favorites: [Track] = []
    var playlists: [Playlist] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var playbackSession = PlaybackSession()
}
