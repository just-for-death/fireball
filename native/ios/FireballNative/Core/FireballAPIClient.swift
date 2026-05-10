import Foundation

final class FireballAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func iTunesSearch(term: String, limit: Int = 25) async throws -> Data {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func invidiousSearch(instanceURL: String, query: String, sid: String? = nil) async throws -> Data {
        var components = URLComponents(string: instanceURL)!
        components.path = "/api/v1/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video")
        ]
        var request = URLRequest(url: components.url!)
        if let sid, !sid.isEmpty {
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    func invidiousVideo(instanceURL: String, videoId: String, sid: String? = nil) async throws -> Data {
        var components = URLComponents(string: instanceURL)!
        components.path = "/api/v1/videos/\(videoId)"
        var request = URLRequest(url: components.url!)
        if let sid, !sid.isEmpty {
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    func pipedSearch(instanceURL: String, query: String) async throws -> Data {
        var components = URLComponents(string: instanceURL)!
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "filter", value: "music_songs")
        ]
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func pipedStream(instanceURL: String, videoId: String) async throws -> Data {
        var components = URLComponents(string: instanceURL)!
        components.path = "/streams/\(videoId)"
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func lrclibSearch(track: String, artist: String) async throws -> Data {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func neteaseSearch(query: String) async throws -> Data {
        var components = URLComponents(string: "https://music.163.com/api/search/get")!
        components.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func neteaseLyrics(songId: String) async throws -> Data {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")!
        components.queryItems = [
            URLQueryItem(name: "id", value: songId),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        let (data, _) = try await session.data(from: components.url!)
        return data
    }

    func ollamaGenerate(ollamaUrl: String, model: String, prompt: String) async throws -> Data {
        let base = ollamaUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: "\(base)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": prompt]]
        ])
        return try await session.data(for: request).0
    }
}
