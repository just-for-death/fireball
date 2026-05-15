import XCTest
@testable import FireballNativeCore

final class FireballRepositoryLinuxTests: XCTestCase {

    func testInvidiousOrderingPrefersUserInstance() {
        let ordered = InvidiousInstances.ordered(
            userInstance: "https://my.invidious.example",
            publicInstances: ["https://public.example"]
        )
        XCTAssertEqual(ordered.first, "https://my.invidious.example")
        XCTAssertTrue(ordered.contains("https://public.example"))
    }

    func testYoutubeSearchHTMLParsing() {
        let html = """
        {"videoId":"dQw4w9WgXcQ","title":{"simpleText":"Test"}}
        {"videoId":"abcdefghijk","title":{"simpleText":"Dup"}}
        """
        XCTAssertEqual(YoutubeDirectStreamResolver.parseFirstVideoId(fromSearchHTML: html), "dQw4w9WgXcQ")
    }

    func testYoutubeSearchHTMLParsingEmpty() {
        XCTAssertNil(YoutubeDirectStreamResolver.parseFirstVideoId(fromSearchHTML: "no ids here"))
    }
}
