import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(YouTubeKit)
import YouTubeKit
#endif

/// On-device YouTube audio when Invidious is unavailable.
/// Primary: portable InnerTube (Linux-testable). Optional: YouTubeKit on Apple when linked in CI/Xcode.
enum YoutubeDirectStreamResolver {

    /// Best-effort audio URL for a known YouTube video id.
    static func resolveAudioUrl(videoId: String, highQuality: Bool) async -> String? {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count >= 8 else { return nil }
        return await Task.detached(priority: .userInitiated) {
            await pickAudioUrl(videoId: id, highQuality: highQuality)
        }.value
    }

    /// Finds a likely music video via YouTube search, then resolves audio. Returns (videoId, url).
    static func searchAndResolveAudio(artist: String, title: String, highQuality: Bool) async -> (String, String)? {
        let queries = [
            "\(artist) \(title) official audio",
            "\(artist) \(title) audio",
            "\(artist) - \(title)",
        ]
        for query in queries {
            guard let videoId = await findFirstVideoId(query: query) else { continue }
            if let url = await resolveAudioUrl(videoId: videoId, highQuality: highQuality) {
                return (videoId, url)
            }
        }
        return nil
    }

    private static func pickAudioUrl(videoId: String, highQuality: Bool) async -> String? {
        if let url = await YoutubeInnerTubeClient.resolveAudioStreamURL(
            videoId: videoId,
            highQuality: highQuality
        ), !url.isEmpty {
            return url
        }
        #if canImport(YouTubeKit)
        return await pickAudioUrlWithYouTubeKit(videoId: videoId, highQuality: highQuality)
        #else
        return nil
        #endif
    }

    #if canImport(YouTubeKit)
    private static func pickAudioUrlWithYouTubeKit(videoId: String, highQuality: Bool) async -> String? {
        do {
            let youtube = YouTube(videoID: videoId, methods: [.local, .remote])
            let audioStreams = try await youtube.streams.filterAudioOnly()
            let stream = highQuality
                ? audioStreams.highestAudioBitrateStream()
                : audioStreams.lowestAudioBitrateStream()
            if let url = stream?.url.absoluteString, !url.isEmpty {
                return url
            }
            let combined = try await youtube.streams.filterVideoAndAudio()
            let fallback = highQuality
                ? combined.highestAudioBitrateStream()
                : combined.lowestAudioBitrateStream()
            return fallback?.url.absoluteString
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Search (HTML scrape; no Invidious)

    private static func findFirstVideoId(query: String) async -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAQ%253D%253D")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue(FireballAPIClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 399).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        return parseFirstVideoId(fromSearchHTML: html)
    }

    /// First unique `videoId` in YouTube search results HTML (testable without network).
    static func parseFirstVideoId(fromSearchHTML html: String) -> String? {
        let pattern = #""videoId":"([a-zA-Z0-9_-]{11})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: html)
            else { continue }
            let id = String(html[idRange])
            if seen.insert(id).inserted { return id }
        }
        return nil
    }
}
