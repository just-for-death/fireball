import Foundation

/// Pure helpers for followed-artist iTunes release polling (Android + iOS parity).
enum ArtistReleaseProbe {
    struct AlbumHit: Equatable {
        let collectionId: String
        let collectionName: String
    }

    enum ReleaseOutcome: Equatable {
        case unchanged
        case baselineStored
        case notifyNewRelease
    }

    struct ReleaseEvaluation: Equatable {
        let artist: Artist
        let outcome: ReleaseOutcome
    }

    static func resolveNumericItunesArtistId(
        storedArtistId: String,
        artistName: String,
        lookupByName: (String) -> Int?
    ) -> Int? {
        if let stored = Int(storedArtistId.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return stored
        }
        return lookupByName(artistName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func evaluateNewRelease(
        artist: Artist,
        resolvedArtistId: String,
        latestAlbum: AlbumHit?
    ) -> ReleaseEvaluation {
        var working = artist
        if resolvedArtistId != artist.artistId {
            working = Artist(
                artistId: resolvedArtistId,
                name: artist.name,
                artwork: artist.artwork,
                latestReleaseId: artist.latestReleaseId
            )
        }
        guard let hit = latestAlbum else {
            return ReleaseEvaluation(artist: working, outcome: .unchanged)
        }
        if hit.collectionId == working.latestReleaseId {
            return ReleaseEvaluation(artist: working, outcome: .unchanged)
        }
        let updated = Artist(
            artistId: working.artistId,
            name: working.name,
            artwork: working.artwork,
            latestReleaseId: hit.collectionId
        )
        if working.latestReleaseId == nil {
            return ReleaseEvaluation(artist: updated, outcome: .baselineStored)
        }
        return ReleaseEvaluation(artist: updated, outcome: .notifyNewRelease)
    }

    static func notificationCopy(artistName: String, albumName: String) -> (title: String, message: String) {
        ("New Release from \(artistName)", "\(albumName) is out now!")
    }
}
