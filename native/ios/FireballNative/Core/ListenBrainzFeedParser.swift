import Foundation

enum ListenBrainzFeedParser {
    static func parseRecentListens(_ data: Data) -> [Track] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let listens = payload["listens"] as? [[String: Any]] else {
            return []
        }
        return listens.compactMap(parseRecentEntry)
    }

    static func parseTopRecordings(_ data: Data) -> [Track] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let recordings = payload["recordings"] as? [[String: Any]] else {
            return []
        }
        return recordings.compactMap(parseTopEntry)
    }

    private static func parseRecentEntry(_ listen: [String: Any]) -> Track? {
        guard let meta = listen["track_metadata"] as? [String: Any] else { return nil }
        let title = (meta["track_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = (meta["artist_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return Track(
            id: "\(artist)::\(title)",
            videoId: nil,
            title: title,
            artist: artist,
            artwork: nil,
            url: nil,
            duration: nil,
            album: meta["release_name"] as? String,
            year: nil
        )
    }

    private static func parseTopEntry(_ rec: [String: Any]) -> Track? {
        let title = (rec["track_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = (rec["artist_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return Track(
            id: "\(artist)::\(title)",
            videoId: nil,
            title: title,
            artist: artist,
            artwork: nil,
            url: nil,
            duration: nil,
            album: rec["release_name"] as? String,
            year: nil
        )
    }
}
