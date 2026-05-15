import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SponsorSegment: Codable, Hashable {
    let segment: [Double]
    let category: String
    let uuid: String

    enum CodingKeys: String, CodingKey {
        case segment
        case category
        case uuid = "UUID"
    }

    var start: Double { segment.count > 0 ? segment[0] : 0 }
    var end: Double { segment.count > 1 ? segment[1] : 0 }
}

final class SponsorBlockClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func segments(videoId: String, categories: [String]) async -> [SponsorSegment] {
        guard !videoId.isEmpty, !categories.isEmpty else { return [] }
        var components = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")!
        let categoriesJSON = "[\"\(categories.joined(separator: "\",\""))\"]"
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoId),
            URLQueryItem(name: "categories", value: categoriesJSON),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(FireballAPIClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        guard let data = try? await session.data(for: request).0 else { return [] }
        return (try? JSONDecoder().decode([SponsorSegment].self, from: data)) ?? []
    }

    func markViewed(uuid: String) async {
        guard !uuid.isEmpty else { return }
        var components = URLComponents(string: "https://sponsor.ajay.app/api/viewedVideoSponsorTime")!
        components.queryItems = [URLQueryItem(name: "UUID", value: uuid)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(FireballAPIClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        _ = try? await session.data(for: request)
    }
}

final class ListenBrainzClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func submitPlayingNow(token: String, title: String, artist: String) async {
        await submit(token: token, listenType: "playing_now", title: title, artist: artist, listenedAt: nil)
    }

    func submitScrobble(token: String, title: String, artist: String, listenedAt: Int64) async {
        await submit(token: token, listenType: "single", title: title, artist: artist, listenedAt: listenedAt)
    }

    private func submit(token: String, listenType: String, title: String, artist: String, listenedAt: Int64?) async {
        guard !token.isEmpty, !title.isEmpty, !artist.isEmpty else { return }
        let payloadItem: [String: Any] = {
            var dict: [String: Any] = [
                "track_metadata": [
                    "track_name": title,
                    "artist_name": artist
                ]
            ]
            if let listenedAt { dict["listened_at"] = listenedAt }
            return dict
        }()

        let root: [String: Any] = ["listen_type": listenType, "payload": [payloadItem]]
        guard let body = try? JSONSerialization.data(withJSONObject: root) else { return }

        var request = URLRequest(url: URL(string: "https://api.listenbrainz.org/1/submit-listens")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }
}

final class WebDavSyncClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func pullLibraryJson(baseURL: String, username: String, password: String) async -> String? {
        guard let url = URL(string: normalizedPath(baseURL: baseURL)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyBasicAuth(to: &request, username: username, password: password)
        guard let data = try? await session.data(for: request).0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func pushLibraryJson(baseURL: String, username: String, password: String, json: String) async -> Bool {
        guard let url = URL(string: normalizedPath(baseURL: baseURL)) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = json.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyBasicAuth(to: &request, username: username, password: password)
        return (try? await session.data(for: request)) != nil
    }

    private func normalizedPath(baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/fireball/library.json"
    }

    private func applyBasicAuth(to request: inout URLRequest, username: String, password: String) {
        guard !username.isEmpty || !password.isEmpty else { return }
        let raw = "\(username):\(password)"
        let value = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(value)", forHTTPHeaderField: "Authorization")
    }
}
