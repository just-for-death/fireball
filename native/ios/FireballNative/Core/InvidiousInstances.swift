import Foundation

/// Official trusted Invidious instances (May 2026 — https://docs.invidious.io/instances/).
enum InvidiousInstances {
    static let trusted: [String] = [
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://inv.thepixora.com",
        "https://yt.chocolatemoo53.com",
    ]

    private static var cachedRemote: [String]?
    private static var cachedAt: TimeInterval = 0
    private static let cacheTTL: TimeInterval = 3600

    /// User instance first, then live + trusted public mirrors.
    static func ordered(userInstance: String, publicInstances: [String]) -> [String] {
        let user = userInstance.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var out: [String] = []
        if !user.isEmpty { out.append(user) }
        for uri in publicInstances + trusted {
            let normalized = uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !normalized.isEmpty, normalized != user, !out.contains(normalized) {
                out.append(normalized)
            }
        }
        return out
    }

    static func fetchHealthyPublicInstances(session: URLSession = .shared) async -> [String] {
        let now = Date().timeIntervalSince1970
        if let cached = cachedRemote, now - cachedAt < cacheTTL {
            return cached
        }

        guard let url = URL(string: "https://api.invidious.io/instances.json?sort_by=health") else {
            return trusted
        }

        let parsed: [String] = await {
            guard let (data, _) = try? await session.data(from: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [[Any]]
            else { return [] }

            return root.compactMap { entry -> String? in
                guard entry.count >= 2,
                      let meta = entry[1] as? [String: Any],
                      (meta["type"] as? String) == "https",
                      let uri = meta["uri"] as? String
                else { return nil }
                if let monitor = meta["monitor"] as? [String: Any],
                   (monitor["down"] as? Bool) == true {
                    return nil
                }
                return uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }()

        let merged = Array(Set(parsed + trusted))
        cachedRemote = merged
        cachedAt = now
        return merged
    }
}
