import Foundation
import Observation

/// Your dictionary: "when Utter writes this, change it to that".
/// Saved as a small JSON file on the phone, separate from history.
@Observable
final class Vocabulary {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var heard: String   // what the model writes, e.g. "vox two"
        var write: String   // what you want, e.g. "Vox2"
    }

    private(set) var entries: [Entry] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    /// Adds or updates a fix. Returns false if it's empty or would do nothing.
    @discardableResult
    func save(heard: String, write: String, replacing id: UUID? = nil) -> Bool {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let write = write.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !write.isEmpty, heard != write else { return false }
        // One rule per heard phrase: a newer one replaces the old.
        entries.removeAll { $0.id == id || Self.key($0.heard) == Self.key(heard) }
        entries.insert(Entry(heard: heard, write: write), at: 0)
        persist()
        return true
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// The words you want spelled your way, for Whisper's hint.
    var hintWords: [String] { entries.map(\.write) }

    // MARK: Applying

    /// Swaps in your spellings. Matches whole words, ignoring case and punctuation,
    /// and keeps the punctuation that was attached ("vox two," → "Vox2,").
    func apply(to transcript: Transcript) -> Transcript {
        guard !entries.isEmpty else { return transcript }
        let rules = entries.map { (heard: $0.heard.split(separator: " ").map { Self.key(String($0)) }, write: $0.write) }
            .sorted { $0.heard.count > $1.heard.count }   // longer phrases first
        var words = transcript.words
        var out: [ScoredWord] = []
        var i = 0
        while i < words.count {
            var matched = false
            for rule in rules where !rule.heard.isEmpty && i + rule.heard.count <= words.count {
                let slice = words[i..<(i + rule.heard.count)]
                guard zip(slice, rule.heard).allSatisfy({ Self.key($0.text) == $1 }) else { continue }
                let first = slice.first!, last = slice.last!
                var text = rule.write + Self.trailingPunctuation(last.text)
                // Keep a capital at the start of a sentence.
                if let c = first.text.first, c.isUppercase, let w = text.first, w.isLowercase,
                   out.isEmpty || out.last!.text.last.map({ ".?!".contains($0) }) == true {
                    text = text.prefix(1).uppercased() + text.dropFirst()
                }
                out.append(ScoredWord(text: text, confidence: slice.map(\.confidence).max() ?? 1,
                                      startsParagraph: first.startsParagraph))
                i += rule.heard.count
                matched = true
                break
            }
            if !matched { out.append(words[i]); i += 1 }
        }
        words = out
        return Transcript(words: words)
    }

    /// If an edit changed exactly one word, that's a fix worth offering to remember.
    static func singleWordFix(from original: String, to edited: String) -> (heard: String, write: String)? {
        let a = original.split(whereSeparator: \.isWhitespace), b = edited.split(whereSeparator: \.isWhitespace)
        guard a.count == b.count else { return nil }
        let changed = zip(a, b).filter { key(String($0)) != key(String($1)) }
        guard changed.count == 1, let pair = changed.first else { return nil }
        let heard = String(pair.0).trimmingCharacters(in: .punctuationCharacters)
        let write = String(pair.1).trimmingCharacters(in: .punctuationCharacters)
        return heard.isEmpty || write.isEmpty ? nil : (heard, write)
    }

    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    private static func trailingPunctuation(_ word: String) -> String {
        String(word.reversed().prefix { $0.isPunctuation }.reversed())
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
