import Foundation

enum ItunesFeedParser {
    struct ChartEntry {
        let id: String
        let title: String
        let artist: String
        let artwork: String?
    }

    static func feedEntries(from data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any],
              let entry = feed["entry"] else {
            return []
        }
        if let list = entry as? [[String: Any]] { return list }
        if let one = entry as? [String: Any] { return [one] }
        return []
    }

    static func topCharts(from entries: [[String: Any]]) -> [ChartEntry] {
        entries.compactMap { e in
            guard let idObj = e["id"] as? [String: Any],
                  let attrs = idObj["attributes"] as? [String: Any],
                  let id = attrs["im:id"] as? String,
                  !id.isEmpty else {
                return nil
            }
            let title = (e["im:name"] as? [String: Any])?["label"] as? String ?? "—"
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String ?? "—"
            let images = e["im:image"] as? [[String: Any]]
            let artwork = images?.dropFirst(2).first?["label"] as? String ?? images?.last?["label"] as? String
            return ChartEntry(
                id: id,
                title: title,
                artist: artist,
                artwork: artwork
            )
        }
    }
}
