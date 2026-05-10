import Foundation

final class LibraryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseDirectory: URL) {
        self.fileURL = baseDirectory.appendingPathComponent("fireball_library.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: fileURL) else {
            return LibrarySnapshot()
        }
        return (try? decoder.decode(LibrarySnapshot.self, from: data)) ?? LibrarySnapshot()
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        let tempURL = fileURL.deletingPathExtension().appendingPathExtension("tmp")
        let data = try encoder.encode(snapshot)
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }
}
