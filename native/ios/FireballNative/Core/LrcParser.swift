import Foundation

struct LrcLine: Equatable {
    let timeMs: Int64
    let text: String
}

enum LrcParser {
    private static let timestampRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]"#
    )

    static func parse(_ raw: String) -> [LrcLine] {
        var lines: [LrcLine] = []
        for line in raw.components(separatedBy: .newlines) {
            lines.append(contentsOf: parseLine(line))
        }
        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    private static func parseLine(_ line: String) -> [LrcLine] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = timestampRegex.matches(in: trimmed, range: fullRange)
        guard let last = matches.last else { return [] }
        let textStart = last.range.location + last.range.length
        guard textStart <= ns.length else { return [] }
        let text = ns.substring(from: textStart).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return matches.compactMap { result -> LrcLine? in
            guard result.numberOfRanges >= 4 else { return nil }
            let min = Int64(ns.substring(with: result.range(at: 1))) ?? 0
            let sec = Int64(ns.substring(with: result.range(at: 2))) ?? 0
            let fracStr = result.range(at: 3).location != NSNotFound
                ? ns.substring(with: result.range(at: 3))
                : ""
            let msFrac: Int64 = {
                if fracStr.isEmpty { return 0 }
                if fracStr.count == 2 { return (Int64(fracStr) ?? 0) * 10 }
                let padded = fracStr.padding(toLength: 3, withPad: "0", startingAt: 0)
                return Int64(padded) ?? 0
            }()
            return LrcLine(timeMs: min * 60_000 + sec * 1_000 + msFrac, text: text)
        }
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
