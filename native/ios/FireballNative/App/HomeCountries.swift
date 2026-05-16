import Foundation

enum HomeCountries {
    static let all: [(code: String, name: String)] = [
        ("US", "United States"),
        ("GB", "United Kingdom"),
        ("IN", "India"),
        ("JP", "Japan"),
        ("DE", "Germany"),
        ("FR", "France"),
        ("BR", "Brazil"),
        ("CA", "Canada"),
        ("AU", "Australia"),
        ("KR", "South Korea"),
    ]

    static let defaultCodes: Set<String> = ["US", "GB", "IN", "JP", "DE"]

    static func visibleCodes(saved: [String]) -> [String] {
        saved.isEmpty ? Array(defaultCodes) : saved
    }
}
