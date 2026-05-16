import XCTest
@testable import FireballNativeCore

final class ArtistNameParserTests: XCTestCase {
    func testSingleArtist() {
        XCTAssertEqual(ArtistNameParser.splitArtists("Taylor Swift"), ["Taylor Swift"])
    }

    func testAmpersand() {
        XCTAssertEqual(
            ArtistNameParser.splitArtists("Ella Langley & Riley Green"),
            ["Ella Langley", "Riley Green"]
        )
    }

    func testFeat() {
        XCTAssertEqual(
            ArtistNameParser.splitArtists("Post Malone feat. Swae Lee"),
            ["Post Malone", "Swae Lee"]
        )
    }

    func testXSeparator() {
        XCTAssertEqual(ArtistNameParser.splitArtists("John x Jane"), ["John", "Jane"])
        XCTAssertEqual(ArtistNameParser.splitArtists("Gen X"), ["Gen X"])
    }
}
