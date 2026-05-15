import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Portable YouTube stream discovery via InnerTube + watch HTML (no YouTubeKit / no Mac toolchain).
/// Used as the primary iOS fallback when Invidious fails; fully testable on Linux.
enum YoutubeInnerTubeClient {

    private struct ClientProfile {
        let name: String
        let version: String
        let apiKey: String
        let clientId: String
        let userAgent: String
    }

    /// Ordered by likelihood of direct (non-cipher) audio URLs on music content.
    private static let profiles: [ClientProfile] = [
        ClientProfile(
            name: "ANDROID_MUSIC",
            version: "5.16.51",
            apiKey: "AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI",
            clientId: "21",
            userAgent: "com.google.android.apps.youtube.music/5.16.51 (Linux; U; Android 11) gzip"
        ),
        ClientProfile(
            name: "ANDROID",
            version: "20.10.38",
            apiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
            clientId: "3",
            userAgent: "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip"
        ),
        ClientProfile(
            name: "IOS",
            version: "20.10.4",
            apiKey: "",
            clientId: "5",
            userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
        ),
        ClientProfile(
            name: "WEB",
            version: "2.20260114.08.00",
            apiKey: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            clientId: "1",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        ),
    ]

    static func resolveAudioStreamURL(videoId: String, highQuality: Bool, session: URLSession = .shared) async -> String? {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count >= 8 else { return nil }

        for profile in profiles {
            if let url = await fetchPlayerStream(
                videoId: id,
                profile: profile,
                highQuality: highQuality,
                session: session
            ) {
                return url
            }
        }

        if let html = await fetchWatchHTML(videoId: id, session: session),
           let root = parseInitialPlayerResponse(from: html) {
            return pickPlaybackURL(from: root, highQuality: highQuality)
        }

        return nil
    }

    // MARK: - InnerTube player

    private static func fetchPlayerStream(
        videoId: String,
        profile: ClientProfile,
        highQuality: Bool,
        session: URLSession
    ) async -> String? {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "contentCheckOk", value: "true"),
            URLQueryItem(name: "racyCheckOk", value: "true"),
        ]
        if !profile.apiKey.isEmpty {
            query.append(URLQueryItem(name: "key", value: profile.apiKey))
        }
        components.queryItems = query

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": profile.name,
                    "clientVersion": profile.version,
                    "hl": "en",
                    "gl": "US",
                ],
            ],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        guard let url = components.url,
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(profile.clientId, forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(profile.version, forHTTPHeaderField: "X-Youtube-Client-Version")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 399).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let status = (root["playabilityStatus"] as? [String: Any])?["status"] as? String,
           status != "OK" {
            return nil
        }

        return pickPlaybackURL(from: root, highQuality: highQuality)
    }

    // MARK: - Watch page

    private static func fetchWatchHTML(videoId: String, session: URLSession) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&bpctr=9999999999&has_verified=1")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(FireballAPIClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 399).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return html
    }

    static func parseInitialPlayerResponse(from html: String) -> [String: Any]? {
        let markers = [
            "ytInitialPlayerResponse = ",
            "var ytInitialPlayerResponse = ",
        ]
        for marker in markers {
            guard let start = html.range(of: marker) else { continue }
            let jsonStart = start.upperBound
            guard let json = extractJSONObject(from: html, startingAt: jsonStart) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    private static func extractJSONObject(from html: String, startingAt index: String.Index) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = index
        let end = html.endIndex
        while i < end {
            let ch = html[i]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(html[index ... i])
                    }
                }
            }
            i = html.index(after: i)
        }
        return nil
    }

    // MARK: - Format selection

    static func pickPlaybackURL(from playerResponse: [String: Any], highQuality: Bool) -> String? {
        guard let streaming = playerResponse["streamingData"] as? [String: Any] else { return nil }

        if let hls = streaming["hlsManifestUrl"] as? String, !hls.isEmpty {
            return hls
        }

        var formats: [[String: Any]] = []
        if let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] {
            formats.append(contentsOf: adaptive)
        }
        if let progressive = streaming["formats"] as? [[String: Any]] {
            formats.append(contentsOf: progressive)
        }

        let audio = formats.filter { format in
            guard let url = format["url"] as? String, !url.isEmpty else { return false }
            if format["signatureCipher"] != nil || format["cipher"] != nil { return false }
            let mime = (format["mimeType"] as? String) ?? ""
            return mime.hasPrefix("audio/") || mime.contains("audio")
        }

        let sorted = audio.sorted { bitrate($0) < bitrate($1) }
        guard !sorted.isEmpty else { return nil }
        let pick = highQuality ? sorted.last : sorted.first
        return pick?["url"] as? String
    }

    private static func bitrate(_ format: [String: Any]) -> Int {
        if let n = format["bitrate"] as? Int { return n }
        if let n = format["averageBitrate"] as? Int { return n }
        if let s = format["bitrate"] as? String, let n = Int(s) { return n }
        return 0
    }
}
