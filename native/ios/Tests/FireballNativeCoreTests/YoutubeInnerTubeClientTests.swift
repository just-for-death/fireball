import XCTest
@testable import FireballNativeCore

final class YoutubeInnerTubeClientTests: XCTestCase {

    func testPickAudioURLFromAdaptiveFormats() {
        let response: [String: Any] = [
            "streamingData": [
                "adaptiveFormats": [
                    [
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                        "bitrate": 128_000,
                        "url": "https://example.com/low.m4a",
                    ],
                    [
                        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                        "bitrate": 256_000,
                        "url": "https://example.com/high.m4a",
                    ],
                    [
                        "mimeType": "video/mp4",
                        "bitrate": 1_000_000,
                        "url": "https://example.com/video.mp4",
                    ],
                ],
            ],
        ]
        XCTAssertEqual(
            YoutubeInnerTubeClient.pickPlaybackURL(from: response, highQuality: true),
            "https://example.com/high.m4a"
        )
        XCTAssertEqual(
            YoutubeInnerTubeClient.pickPlaybackURL(from: response, highQuality: false),
            "https://example.com/low.m4a"
        )
    }

    func testPickHLSWhenPresent() {
        let response: [String: Any] = [
            "streamingData": [
                "hlsManifestUrl": "https://example.com/master.m3u8",
                "adaptiveFormats": [
                    ["mimeType": "audio/mp4", "url": "https://example.com/a.m4a", "bitrate": 1],
                ],
            ],
        ]
        XCTAssertEqual(
            YoutubeInnerTubeClient.pickPlaybackURL(from: response, highQuality: true),
            "https://example.com/master.m3u8"
        )
    }

    func testSkipsCipheredFormats() {
        let response: [String: Any] = [
            "streamingData": [
                "adaptiveFormats": [
                    [
                        "mimeType": "audio/mp4",
                        "signatureCipher": "url=foo",
                    ],
                ],
            ],
        ]
        XCTAssertNil(YoutubeInnerTubeClient.pickPlaybackURL(from: response, highQuality: true))
    }

    func testParseInitialPlayerResponseFromHTML() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"abc123XYZ01"},"streamingData":{"hlsManifestUrl":"https://example.com/hls.m3u8"}};</script>
        """
        let root = YoutubeInnerTubeClient.parseInitialPlayerResponse(from: html)
        XCTAssertNotNil(root)
        XCTAssertEqual(
            YoutubeInnerTubeClient.pickPlaybackURL(from: root!, highQuality: true),
            "https://example.com/hls.m3u8"
        )
    }
}
