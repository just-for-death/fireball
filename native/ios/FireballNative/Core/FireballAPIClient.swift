import Foundation

private final class InvidiousLoginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class FireballAPIClient {
    private let session: URLSession
    private let loginDelegate = InvidiousLoginRedirectDelegate()
    private lazy var loginSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.httpCookieAcceptPolicy = .never
        return URLSession(configuration: cfg, delegate: loginDelegate, delegateQueue: nil)
    }()

    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 FireballNative/1.0"

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func applyDefaultHeaders(_ request: inout URLRequest) {
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    }

    private func trimTrailingSlashes(_ url: String) -> String {
        var s = url
        while s.last == "/" { s.removeLast() }
        return s
    }

    func iTunesSearch(term: String, limit: Int = 25) async throws -> Data {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        var request = URLRequest(url: components.url!)
        applyDefaultHeaders(&request)
        let (data, _) = try await session.data(for: request)
        return data
    }

    func invidiousSearch(instanceURL: String, query: String, sid: String? = nil) async throws -> Data {
        let base = trimTrailingSlashes(instanceURL)
        var c = URLComponents(string: "\(base)/api/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        applyDefaultHeaders(&request)
        if let sid, !sid.isEmpty {
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    /// `local=true` proxies streams through the instance (recommended for playback).
    /// `local=true` asks Invidious to proxy stream URLs (recommended for playback).
    func invidiousVideo(
        instanceURL: String,
        videoId: String,
        sid: String? = nil,
        local: Bool = true
    ) async throws -> Data {
        let base = trimTrailingSlashes(instanceURL)
        let encodedId = videoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoId
        var components = URLComponents(string: "\(base)/api/v1/videos/\(encodedId)")!
        if local {
            components.queryItems = [URLQueryItem(name: "local", value: "true")]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        applyDefaultHeaders(&request)
        if let sid, !sid.isEmpty {
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    /// POST to Invidious login; does not follow redirects so `Set-Cookie` / `SID` can be read from the response.
    func invidiousLogin(instanceURL: String, username: String, password: String) async throws -> (sid: String, username: String) {
        let base = trimTrailingSlashes(instanceURL)
        guard let url = URL(string: "\(base)/login?type=invidious") else { throw URLError(.badURL) }

        func tryLogin(body: String) async throws -> (sid: String, code: Int) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("\(base)/login", forHTTPHeaderField: "Referer")
            request.setValue(base, forHTTPHeaderField: "Origin")
            applyDefaultHeaders(&request)
            request.httpBody = body.data(using: .utf8)
            let (_, response) = try await loginSession.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let sid = extractSid(from: response) ?? ""
            return (sid, code)
        }

        let encUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let encPass = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        var (sid, code) = try await tryLogin(body: "email=\(encUser)&password=\(encPass)")
        if sid.isEmpty {
            (sid, code) = try await tryLogin(body: "email=\(encUser)&password=\(encPass)&action=signin")
        }
        if sid.isEmpty {
            let reason = (code == 401 || code == 403) ? "wrong credentials" : "status=\(code), captcha or login disabled"
            throw NSError(domain: "InvidiousLogin", code: code, userInfo: [NSLocalizedDescriptionKey: "Invidious login failed (\(reason))."])
        }
        return (sid: sid, username: username)
    }

    private func extractSid(from response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse, let url = http.url else { return nil }
        var headerDict = [String: String]()
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headerDict[k] = v
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerDict, for: url)
        if let sid = cookies.first(where: { $0.name.caseInsensitiveCompare("SID") == .orderedSame })?.value, !sid.isEmpty {
            return sid
        }
        var combined = ""
        for (k, v) in headerDict where k.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            combined += v + "\n"
        }
        if let r = try? NSRegularExpression(pattern: "SID=([^;]+)", options: .caseInsensitive),
           let m = r.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           m.numberOfRanges > 1,
           let range = Range(m.range(at: 1), in: combined) {
            return String(combined[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    func invidiousPlaylistDetail(instanceURL: String, sid: String?, playlistId: String) async throws -> Data {
        let base = trimTrailingSlashes(instanceURL)
        let enc = playlistId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? playlistId
        guard let url = URL(string: "\(base)/api/v1/playlists/\(enc)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        applyDefaultHeaders(&request)
        if let sid, !sid.isEmpty {
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    func invidiousAuthPlaylists(instanceURL: String, sid: String) async throws -> Data {
        let base = trimTrailingSlashes(instanceURL)
        guard let url = URL(string: "\(base)/api/v1/auth/playlists") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        applyDefaultHeaders(&request)
        request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        let (data, _) = try await session.data(for: request)
        return data
    }

    func invidiousCreatePlaylist(instanceURL: String, sid: String, title: String, privacy: String) async throws -> String {
        let base = trimTrailingSlashes(instanceURL)
        guard let url = URL(string: "\(base)/api/v1/auth/playlists") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyDefaultHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        let body: [String: Any] = ["title": title, "privacy": privacy]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["playlistId"] as? String) ?? ""
    }

    func invidiousAddVideoToPlaylist(instanceURL: String, sid: String, playlistId: String, videoId: String) async throws {
        let base = trimTrailingSlashes(instanceURL)
        let encPl = playlistId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? playlistId
        guard let url = URL(string: "\(base)/api/v1/auth/playlists/\(encPl)/videos") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyDefaultHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["videoId": videoId])
        _ = try await session.data(for: request)
    }

    func lrclibSearch(track: String, artist: String) async throws -> Data {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        var request = URLRequest(url: components.url!)
        applyDefaultHeaders(&request)
        let (data, _) = try await session.data(for: request)
        return data
    }

    func neteaseSearch(query: String) async throws -> Data {
        var components = URLComponents(string: "https://music.163.com/api/search/get")!
        components.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        var request = URLRequest(url: components.url!)
        applyDefaultHeaders(&request)
        let (data, _) = try await session.data(for: request)
        return data
    }

    func neteaseLyrics(songId: String) async throws -> Data {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")!
        components.queryItems = [
            URLQueryItem(name: "id", value: songId),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        var request = URLRequest(url: components.url!)
        applyDefaultHeaders(&request)
        let (data, _) = try await session.data(for: request)
        return data
    }

    func ollamaGenerate(ollamaUrl: String, model: String, prompt: String) async throws -> Data {
        let base = ollamaUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: "\(base)/api/chat")!)
        request.httpMethod = "POST"
        applyDefaultHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": prompt]],
        ])
        return try await session.data(for: request).0
    }
}
