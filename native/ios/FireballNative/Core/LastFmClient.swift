import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

struct LastFmClient {
    private static let base = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    func validateApiKey(_ apiKey: String) async -> Bool {
        guard !apiKey.isEmpty,
              let url = URL(string: "\(Self.base)?method=chart.gettopartists&limit=1&api_key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)&format=json")
        else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return json["error"] == nil
        } catch {
            return false
        }
    }

    func mobileSession(apiKey: String, apiSecret: String, username: String, password: String) async -> String? {
        guard !apiKey.isEmpty, !apiSecret.isEmpty, !username.isEmpty, !password.isEmpty else { return nil }
        var params: [String: String] = [
            "method": "auth.getMobileSession",
            "username": username,
            "password": md5(password),
            "api_key": apiKey,
        ]
        params["api_sig"] = sign(params, secret: apiSecret)
        guard let url = signedURL(params: params) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = json["session"] as? [String: Any],
                  let key = session["key"] as? String
            else { return nil }
            return key
        } catch {
            return nil
        }
    }

    func updateNowPlaying(apiKey: String, apiSecret: String, sessionKey: String, title: String, artist: String, album: String?) async -> Bool {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": title,
        ]
        if let album, !album.isEmpty { params["album"] = album }
        return await postSigned(params: params, apiSecret: apiSecret)
    }

    func scrobble(apiKey: String, apiSecret: String, sessionKey: String, title: String, artist: String, listenedAt: Int64, album: String?) async -> Bool {
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": title,
            "timestamp": String(listenedAt),
        ]
        if let album, !album.isEmpty { params["album"] = album }
        return await postSigned(params: params, apiSecret: apiSecret)
    }

    private func postSigned(params: [String: String], apiSecret: String) async -> Bool {
        var signed = params
        signed["api_sig"] = sign(params, secret: apiSecret)
        guard let url = signedURL(params: signed) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return json["error"] == nil
        } catch {
            return false
        }
    }

    private func signedURL(params: [String: String]) -> URL? {
        var components = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "format", value: "json")]
        return components?.url
    }

    private func sign(_ params: [String: String], secret: String) -> String {
        let concat = params.keys.sorted().map { $0 + (params[$0] ?? "") }.joined() + secret
        return md5(concat)
    }

    private func md5(_ input: String) -> String {
        #if canImport(CryptoKit)
        return Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02hhx", $0) }.joined()
        #else
        // Linux CI compile path; Last.fm is exercised on Apple devices in production builds.
        return ""
        #endif
    }
}
