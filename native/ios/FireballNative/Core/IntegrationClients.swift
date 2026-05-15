import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private extension URLSession {
    func dataWithRetry(for request: URLRequest, retries: Int = 1) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                return try await data(for: request)
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
}

private extension URLRequest {
    func withTimeout(_ seconds: TimeInterval = 12) -> URLRequest {
        var copy = self
        copy.timeoutInterval = seconds
        return copy
    }
}

final class GotifyClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func send(url: String, token: String, title: String, message: String) async -> Bool {
        guard !url.isEmpty, !token.isEmpty else { return false }
        guard let endpoint = URL(string: "\(url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/message") else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Gotify-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": title, "message": message, "priority": 5
        ])
        guard let (_, response) = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}

final class LbdlClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func authStatus(baseUrl: String, username: String, password: String) async -> Bool {
        guard let url = URL(string: "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/auth/status") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyBasicAuth(&request, username: username, password: password)
        guard let (_, response) = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    func createJob(baseUrl: String, username: String, password: String, links: [String]) async -> String? {
        guard !links.isEmpty else { return nil }
        guard let url = URL(string: "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api/jobs") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyBasicAuth(&request, username: username, password: password)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["links": links])
        guard let data = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["jobId"] as? String
    }

    private func applyBasicAuth(_ request: inout URLRequest, username: String, password: String) {
        guard !username.isEmpty || !password.isEmpty else { return }
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }
}

final class RemoteLanClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func sendCommand(host: String, port: Int, action: String, value: String? = nil) async -> Bool {
        let safePort = port <= 0 ? 7771 : port
        guard let url = URL(string: "http://\(host):\(safePort)/command") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": action,
            "value": value as Any
        ])
        guard let (_, response) = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    func pair(host: String, port: Int, code: String) async -> Bool {
        guard !code.isEmpty else { return false }
        let safePort = port <= 0 ? 7771 : port
        guard let url = URL(string: "http://\(host):\(safePort)/pair") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        guard let (_, response) = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}

final class GoogleDriveBackupClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func uploadAppDataJson(accessToken: String, fileName: String, content: String) async -> Bool {
        guard !accessToken.isEmpty else { return false }
        guard let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "fireball_native_boundary"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let metadata = #"{"name":"\#(fileName)","parents":["appDataFolder"]}"#
        request.httpBody = """
--\(boundary)
Content-Type: application/json; charset=UTF-8

\(metadata)
--\(boundary)
Content-Type: application/json

\(content)
--\(boundary)--
""".data(using: .utf8)
        guard let (_, response) = try? await session.dataWithRetry(for: request.withTimeout(), retries: 1),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
