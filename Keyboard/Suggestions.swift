import UIKit

/// Word suggestions and gentle autocorrect for the Utter keyboard, from Apple's on-device
/// spell checker (UITextChecker) and the person's own word list (text replacements and
/// contact names, via UILexicon). Nothing leaves the phone, and nothing is learned beyond
/// the words someone keeps on purpose.
///
/// The checker can take many seconds the first time (iOS loads its word lists), so all of this
/// runs on `queue`, never on the keyboard's main thread: typing must never wait for it.
final class Suggester {
    let queue = DispatchQueue(label: "utter.keyboard.suggest", qos: .userInitiated)
    private let checker = UITextChecker()
    private var lexicon: [UILexiconEntry] = []
    /// words the person undid a correction for this session: never "fix" them again
    private var keepAsTyped: Set<String> = []
    private let language: String

    init() {
        let preferred = Locale.preferredLanguages.first?.replacingOccurrences(of: "-", with: "_") ?? "en_US"
        language = UITextChecker.availableLanguages.contains(preferred) ? preferred : "en_US"
    }

    func use(_ lexicon: UILexicon) {
        let entries = lexicon.entries
        queue.async { self.lexicon = entries }
    }

    /// Loads the word lists early, so the first suggestion doesn't lag.
    func warmUp() { queue.async { _ = self.completions(for: "the") } }

    struct Result {
        var words: [String] = []
        /// which of `words` space will put in (an autocorrection), if any
        var best: Int?
    }

    /// Suggestions for the word being typed. The first slot is always what was typed, in quotes
    /// when it might be a misspelling, so tapping it keeps it.
    func suggest(for word: String) -> Result {
        guard word.count >= 1, word.rangeOfCharacter(from: .letters) != nil else { return Result() }
        var out = Result()
        let lower = word.lowercased()

        if let fix = correction(for: word) {
            out.words = ["“\(word)”", fix]
            out.best = 1
            if let other = guesses(for: word).first(where: { $0.lowercased() != fix.lowercased() }) {
                out.words.append(match(other, to: word))
            }
            return out
        }

        var more: [String] = []
        // shortcuts from Settings → General → Keyboard → Text Replacement
        if let entry = lexicon.first(where: { $0.userInput.lowercased() == lower && $0.userInput != $0.documentText }) {
            more.append(entry.documentText)
        }
        // names from contacts, then common words, that start with what's typed
        more += lexicon.lazy.map(\.documentText)
            .filter { $0.lowercased().hasPrefix(lower) && $0.count > word.count && !$0.contains(" ") }
            .prefix(2)
        more += completions(for: word).prefix(4)
        var seen: Set<String> = [lower]
        let picks = more.filter { seen.insert($0.lowercased()).inserted }.prefix(2).map { match($0, to: word) }
        guard !picks.isEmpty else { return Result() }
        out.words = [word] + picks
        return out
    }

    /// What space should turn this word into, or nil to leave it. Only small, confident fixes:
    /// a text replacement shortcut, "i" → "I", or a misspelling one or two letters from a real word.
    func correction(for word: String) -> String? {
        guard word.count >= 1, !keepAsTyped.contains(word.lowercased()) else { return nil }
        if let entry = lexicon.first(where: { $0.userInput.lowercased() == word.lowercased() && $0.userInput != $0.documentText }),
           entry.documentText.contains(" ") || entry.documentText.count > word.count + 2 {
            return entry.documentText   // a real shortcut ("omw" → "On my way!"), not just a contact name
        }
        if word == "i" { return "I" }
        guard word.count >= 2, isMisspelled(word), !isKnownName(word) else { return nil }
        let limit = word.count <= 4 ? 1 : 2
        guard let guess = guesses(for: word).first,
              distance(word.lowercased(), guess.lowercased()) <= limit else { return nil }
        return match(guess, to: word)
    }

    /// The person undid a correction: keep their word from now on, and teach the checker.
    func keep(_ word: String) {
        queue.async {
            self.keepAsTyped.insert(word.lowercased())
            UITextChecker.learnWord(word)
        }
    }

    // MARK: Helpers

    private func isMisspelled(_ word: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location != NSNotFound
    }

    private func isKnownName(_ word: String) -> Bool {
        lexicon.contains { $0.documentText.caseInsensitiveCompare(word) == .orderedSame }
    }

    private func guesses(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.guesses(forWordRange: range, in: word, language: language) ?? []
    }

    private func completions(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
    }

    /// Same capitals as what was typed: "Teh" → "The", "TEH" → "THE".
    private func match(_ s: String, to typed: String) -> String {
        if typed.count > 1, typed == typed.uppercased() { return s.uppercased() }
        if let first = typed.first, first.isUppercase { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// How many single-letter changes turn one word into the other (Levenshtein distance).
    private func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let old = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = old
            }
        }
        return row[b.count]
    }
}
