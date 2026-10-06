import Foundation

/// Small, predictable tidy-ups after transcription.
enum Cleanup {
    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "ah"]

    static func apply(_ transcript: Transcript, removeFillers: Bool) -> Transcript {
        var words = keepParagraphs(transcript.words) { !isNoise($0.text) }
        if removeFillers { words = dropFillers(words) }
        return Transcript(words: words)
    }

    /// Filters words; if a dropped word began a paragraph, the next kept word begins it instead.
    private static func keepParagraphs(_ words: [ScoredWord], where keep: (ScoredWord) -> Bool) -> [ScoredWord] {
        var out: [ScoredWord] = []
        var carry = false
        for var word in words {
            guard keep(word) else { carry = carry || word.startsParagraph; continue }
            if carry { word.startsParagraph = true; carry = false }
            out.append(word)
        }
        if let first = out.first, first.startsParagraph { out[0].startsParagraph = false }
        return out
    }

    /// Whisper sometimes writes sound labels like "[BLANK_AUDIO]" or "(music)".
    private static func isNoise(_ word: String) -> Bool {
        (word.hasPrefix("[") && word.hasSuffix("]")) || (word.hasPrefix("(") && word.hasSuffix(")")) || word == "♪"
    }

    private static func dropFillers(_ words: [ScoredWord]) -> [ScoredWord] {
        var out: [ScoredWord] = []
        var capitalizeNext = false
        var carryParagraph = false
        for (i, word) in words.enumerated() {
            let bare = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if fillers.contains(bare) {
                if word.startsParagraph { carryParagraph = true }
                // "Um, so…" at the start of a sentence: the next word takes the capital.
                let startsSentence = out.isEmpty || out.last!.text.last.map { ".!?".contains($0) } == true
                if startsSentence { capitalizeNext = true }
                // "…and then, um." keeps its full stop on the word before.
                if let end = word.text.last, ".!?".contains(end), !out.isEmpty, i == words.count - 1 || !startsSentence {
                    var last = out.removeLast()
                    last.text = last.text.trimmingCharacters(in: CharacterSet(charactersIn: ",;")) + String(end)
                    out.append(last)
                }
                continue
            }
            var kept = word
            if carryParagraph { kept.startsParagraph = true; carryParagraph = false }
            if capitalizeNext {
                kept.text = kept.text.prefix(1).uppercased() + kept.text.dropFirst()
                capitalizeNext = false
            }
            out.append(kept)
        }
        return out
    }
}
