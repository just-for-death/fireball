import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Lightweight disk cache for stream URLs (iOS parity with Android Exo `SimpleCache`).
enum StreamPlaybackCache {
    private static let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()
    private static let folderName = "stream_playback_cache"

    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func limitBytes(from settings: FireballSettings) -> Int64 {
        let gb = max(1, min(20, settings.localMusicCacheLimit))
        return Int64(gb) * 1_024 * 1_024 * 1_024
    }

    static func cachedFileURL(for remoteURL: URL) -> URL {
        let key = remoteURL.absoluteString.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return cacheDirectory().appendingPathComponent(key + ".cache")
    }

    /// Returns a local `file://` URL when cached bytes exist and caching is enabled.
    static func localPlaybackURL(remoteURL: URL, settings: FireballSettings) -> URL? {
        guard settings.streamCacheEnabled else { return nil }
        let file = cachedFileURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// Best-effort: download remote stream to cache for offline replay within size budget.
    static func prefetch(remoteURL: URL, settings: FireballSettings) async {
        guard settings.streamCacheEnabled else { return }
        let dest = cachedFileURL(for: remoteURL)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        trimIfNeeded(settings: settings)
        guard let (data, _) = try? await urlSession.data(from: remoteURL) else { return }
        try? data.write(to: dest, options: [.atomic])
        trimIfNeeded(settings: settings)
    }

    private static func trimIfNeeded(settings: FireballSettings) {
        let limit = limitBytes(from: settings)
        let dir = cacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in files {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(vals?.fileSize ?? 0)
            total += size
            entries.append((url, size, vals?.contentModificationDate ?? .distantPast))
        }
        guard total > limit else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= limit { break }
        }
    }
}
