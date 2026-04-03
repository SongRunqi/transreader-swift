import Foundation

@Observable
final class VocabStore: @unchecked Sendable {
    private(set) var data: VocabData
    private let vocabURL: URL
    private let queue = DispatchQueue(label: "com.transreader.vocab", qos: .userInitiated)
    
    init(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        self.vocabURL = URL(fileURLWithPath: expanded)
        
        // Ensure parent directory exists
        let parent = vocabURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        
        // Load or create empty
        if let loaded = Self.load(from: vocabURL) {
            self.data = loaded
        } else {
            self.data = .empty
            Self.save(data, to: vocabURL)
        }
    }
    
    private static func load(from url: URL) -> VocabData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VocabData.self, from: data)
    }
    
    private static func save(_ vocab: VocabData, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(vocab) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    func addWord(_ entry: VocabEntry) -> Bool {
        let word = entry.word.lowercased().trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return false }
        
        // Check for duplicates
        if data.words.contains(where: { $0.word.lowercased() == word }) {
            return false
        }
        
        var newEntry = entry
        newEntry.word = word
        if newEntry.addedAt.isEmpty {
            newEntry.addedAt = ISO8601DateFormatter().string(from: Date())
        }
        
        var updated = data
        updated.words.append(newEntry)
        Self.save(updated, to: vocabURL)

        let snapshot = updated
        DispatchQueue.main.async {
            self.data = snapshot
        }
        
        return true
    }
    
    func removeWord(_ word: String) -> Bool {
        let wordLower = word.lowercased().trimmingCharacters(in: .whitespaces)
        let originalCount = data.words.count
        
        var updated = data
        updated.words.removeAll { $0.word.lowercased() == wordLower }

        guard updated.words.count < originalCount else { return false }

        Self.save(updated, to: vocabURL)

        let snapshot = updated
        DispatchQueue.main.async {
            self.data = snapshot
        }
        
        return true
    }
    
    func searchWords(_ query: String) -> [VocabEntry] {
        let queryLower = query.lowercased()
        guard !queryLower.isEmpty else { return data.words }

        return data.words.filter { entry in
            entry.word.lowercased().contains(queryLower) ||
            entry.meanings?.joined().lowercased().contains(queryLower) == true
        }
    }

    // MARK: - Export / Import

    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(data)
    }

    /// Import words from JSON data, merging with existing (skip duplicates).
    /// Returns (added, skipped) counts, or nil if decoding failed.
    func importData(_ jsonData: Data) -> (added: Int, skipped: Int)? {
        guard let imported = try? JSONDecoder().decode(VocabData.self, from: jsonData) else {
            return nil
        }

        let existingWords = Set(data.words.map { $0.word.lowercased() })
        var added = 0
        var skipped = 0
        var updated = data

        for entry in imported.words {
            let word = entry.word.lowercased().trimmingCharacters(in: .whitespaces)
            if existingWords.contains(word) {
                skipped += 1
            } else {
                var newEntry = entry
                newEntry.word = word
                if newEntry.addedAt.isEmpty {
                    newEntry.addedAt = ISO8601DateFormatter().string(from: Date())
                }
                updated.words.append(newEntry)
                added += 1
            }
        }

        if added > 0 {
            Self.save(updated, to: vocabURL)
            let snapshot = updated
            DispatchQueue.main.async {
                self.data = snapshot
            }
        }

        return (added: added, skipped: skipped)
    }
}
