import Foundation

struct LrcLine: Equatable {
    let timeMs: Int64
    let text: String
}

enum LrcParser {
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]\s*(.*)"#
    )

    static func parse(_ raw: String) -> [LrcLine] {
        var lines: [LrcLine] = []
        for match in raw.components(separatedBy: .newlines) {
            let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let result = lineRegex.firstMatch(in: trimmed, range: range) else { continue }
            guard result.numberOfRanges >= 5 else { continue }
            let min = Int64((trimmed as NSString).substring(with: result.range(at: 1))) ?? 0
            let sec = Int64((trimmed as NSString).substring(with: result.range(at: 2))) ?? 0
            let fracStr = result.range(at: 3).location != NSNotFound
                ? (trimmed as NSString).substring(with: result.range(at: 3))
                : ""
            let msFrac: Int64 = {
                if fracStr.isEmpty { return 0 }
                if fracStr.count == 2 { return (Int64(fracStr) ?? 0) * 10 }
                let padded = fracStr.padding(toLength: 3, withPad: "0", startingAt: 0)
                return Int64(padded) ?? 0
            }()
            let text = (trimmed as NSString).substring(with: result.range(at: 4))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append(LrcLine(timeMs: min * 60_000 + sec * 1_000 + msFrac, text: text))
        }
        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    static func hasSyncedTimestamps(_ raw: String) -> Bool { !parse(raw).isEmpty }

    static func activeLineIndex(lines: [LrcLine], positionMs: Int64) -> Int {
        guard !lines.isEmpty else { return -1 }
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.timeMs <= positionMs { idx = i } else { break }
        }
        return idx
    }
}
