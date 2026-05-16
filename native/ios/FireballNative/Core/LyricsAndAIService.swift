import Foundation

@MainActor
final class LyricsAndAIService {
    private let api: FireballAPIClient

    init(api: FireballAPIClient) {
        self.api = api
    }

    func fetchLyrics(track: Track, settings: FireballSettings) async -> String? {
        if let data = try? await api.lrclibSearch(track: track.title, artist: track.artist),
           let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !root.isEmpty {
            let candidates = root.compactMap {
                ($0["syncedLyrics"] as? String) ?? ($0["plainLyrics"] as? String)
            }.filter { !$0.isEmpty }
            if let chosen = choosePreferredLyrics(candidates: candidates, preferEnglishHindi: settings.lyricsPreferEnglishHindi) {
                return chosen
            }
        }

        guard let data = try? await api.neteaseSearch(query: "\(track.title) \(track.artist)"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]],
              let firstId = songs.first?["id"] else { return nil }

        guard let lyricData = try? await api.neteaseLyrics(songId: "\(firstId)"),
              let lyricRoot = try? JSONSerialization.jsonObject(with: lyricData) as? [String: Any],
              let lrc = lyricRoot["lrc"] as? [String: Any],
              let lyric = lrc["lyric"] as? String else { return nil }
        return lyric
    }

    func generateAIQueue(settings: FireballSettings, seed: Track) async -> [String] {
        guard settings.ollamaEnabled, !settings.ollamaUrl.isEmpty else { return [] }
        let prompt = "Suggest 5 songs similar to \(seed.title) by \(seed.artist). Return plain lines: title - artist."
        guard let data = try? await api.ollamaGenerate(
            ollamaUrl: settings.ollamaUrl,
            model: settings.ollamaModel,
            prompt: prompt
        ),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = root["message"] as? [String: Any],
              let content = msg["content"] as? String else { return [] }
        return content.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func choosePreferredLyrics(candidates: [String], preferEnglishHindi: Bool) -> String? {
        guard !candidates.isEmpty else { return nil }
        let synced = candidates.filter { LrcParser.hasSyncedTimestamps($0) }
        let pool = synced.isEmpty ? candidates : synced
        guard preferEnglishHindi else { return pool.first }
        let devanagariRange = Character("\u{0900}") ... Character("\u{097F}")
        return pool.max(by: { score($0, devanagariRange: devanagariRange) < score($1, devanagariRange: devanagariRange) })
    }

    private func score(_ text: String, devanagariRange: ClosedRange<Character>) -> Int {
        let hasEnglish = text.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let hasHindi = text.contains { devanagariRange.contains($0) }
        if hasEnglish && hasHindi { return 3 }
        if hasEnglish { return 2 }
        if hasHindi { return 1 }
        return 0
    }
}
