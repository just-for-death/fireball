import Foundation

/// Splits a display artist line (e.g. "A feat. B & C") into individual artist names.
enum ArtistNameParser {
    private static let separatorPattern =
        #"(?i)\s*(?:,|&|/|\||;|\+)\s*|\s+(?:feat\.?|ft\.?|featuring|with|vs\.?)\s+|\s+x\s+"#

    static func splitArtists(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else {
            return [trimmed]
        }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        var parts: [String] = []
        var last = 0
        regex.enumerateMatches(in: trimmed, range: range) { match, _, _ in
            guard let match, match.range.location >= last else { return }
            let chunk = ns.substring(with: NSRange(location: last, length: match.range.location - last))
            parts.append(chunk)
            last = match.range.location + match.range.length
        }
        if last < ns.length {
            parts.append(ns.substring(from: last))
        }
        if parts.isEmpty {
            return [trimmed]
        }
        var seen = Set<String>()
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
