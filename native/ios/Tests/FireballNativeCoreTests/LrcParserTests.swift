import XCTest
@testable import FireballNativeCore

final class LrcParserTests: XCTestCase {
    func testParseSingleLine() {
        let lines = LrcParser.parse("[00:12.50] Hello world")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timeMs, 12_500)
        XCTAssertEqual(lines[0].text, "Hello world")
    }

    func testParseMultipleTimestamps() {
        let lines = LrcParser.parse("[00:01.00][00:05.00] Same")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Same")
        XCTAssertEqual(lines[1].text, "Same")
    }

    func testSkipsMetadata() {
        let lines = LrcParser.parse("[ar:Artist]\n[00:10.00] Sing")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Sing")
    }
}
