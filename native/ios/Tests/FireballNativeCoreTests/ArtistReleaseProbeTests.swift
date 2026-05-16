import XCTest
@testable import FireballNativeCore

final class ArtistReleaseProbeTests: XCTestCase {
    func testResolveNumericIdPrefersStoredNumeric() {
        let id = ArtistReleaseProbe.resolveNumericItunesArtistId(
            storedArtistId: "12345",
            artistName: "Artist",
            lookupByName: { _ in XCTFail("lookup should not run"); return nil }
        )
        XCTAssertEqual(id, 12345)
    }

    func testResolveNumericIdFallsBackToLookup() {
        let id = ArtistReleaseProbe.resolveNumericItunesArtistId(
            storedArtistId: "Taylor Swift",
            artistName: "Taylor Swift",
            lookupByName: { _ in 999 }
        )
        XCTAssertEqual(id, 999)
    }

    func testEvaluateNewReleaseStoresBaselineWithoutNotify() {
        let artist = Artist(artistId: "1", name: "A", artwork: nil, latestReleaseId: nil)
        let eval = ArtistReleaseProbe.evaluateNewRelease(
            artist: artist,
            resolvedArtistId: "1",
            latestAlbum: ArtistReleaseProbe.AlbumHit(collectionId: "album-1", collectionName: "First Album")
        )
        XCTAssertEqual(eval.outcome, .baselineStored)
        XCTAssertEqual(eval.artist.latestReleaseId, "album-1")
    }

    func testEvaluateNewReleaseNotifiesWhenReleaseChanges() {
        let artist = Artist(artistId: "1", name: "A", artwork: nil, latestReleaseId: "old")
        let eval = ArtistReleaseProbe.evaluateNewRelease(
            artist: artist,
            resolvedArtistId: "1",
            latestAlbum: ArtistReleaseProbe.AlbumHit(collectionId: "new", collectionName: "New Album")
        )
        XCTAssertEqual(eval.outcome, .notifyNewRelease)
        XCTAssertEqual(eval.artist.latestReleaseId, "new")
    }

    func testNotificationCopy() {
        let copy = ArtistReleaseProbe.notificationCopy(artistName: "A", albumName: "B")
        XCTAssertEqual(copy.title, "New Release from A")
        XCTAssertEqual(copy.message, "B is out now!")
    }
}
