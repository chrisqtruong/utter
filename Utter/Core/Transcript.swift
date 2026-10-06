import Foundation

/// One word of a transcript with how sure the model was about it (0–1).
struct ScoredWord: Codable, Hashable {
    var text: String
    var confidence: Float
    /// True when you paused long enough here, at the end of a sentence, to start a new paragraph.
    var startsParagraph = false
    /// When the word was said, in seconds. Only used while building paragraphs; not saved.
    var start: Float = 0
    var end: Float = 0

    init(text: String, confidence: Float, startsParagraph: Bool = false, start: Float = 0, end: Float = 0) {
        self.text = text; self.confidence = confidence; self.startsParagraph = startsParagraph
        self.start = start; self.end = end
    }

    private enum CodingKeys: String, CodingKey { case text, confidence }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        text = try box.decode(String.self, forKey: .text)
        confidence = try box.decode(Float.self, forKey: .confidence)
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(text, forKey: .text)
        try box.encode(confidence, forKey: .confidence)
    }
}

/// What a speech model hands back: the words, each with a confidence.
struct Transcript: Codable, Hashable {
    var words: [ScoredWord]

    init(words: [ScoredWord]) { self.words = words }

    // Saved compactly so years of history stay small: words in one list,
    // confidences as whole percents in another.
    private enum CodingKeys: String, CodingKey { case w, c, p, words }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        if let texts = try box.decodeIfPresent([String].self, forKey: .w) {
            let pcts = try box.decode([UInt8].self, forKey: .c)
            words = zip(texts, pcts).map { ScoredWord(text: $0, confidence: Float($1) / 100) }
            for i in try box.decodeIfPresent([Int].self, forKey: .p) ?? [] where i < words.count {
                words[i].startsParagraph = true
            }
        } else {
            words = try box.decode([ScoredWord].self, forKey: .words)
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(words.map(\.text), forKey: .w)
        try box.encode(words.map { UInt8(max(0, min(100, ($0.confidence * 100).rounded()))) }, forKey: .c)
        let breaks = words.indices.filter { words[$0].startsParagraph }
        if !breaks.isEmpty { try box.encode(breaks, forKey: .p) }
    }

    var text: String {
        var out = ""
        for (i, word) in words.enumerated() {
            if i > 0 { out += word.startsParagraph ? "\n\n" : " " }
            out += word.text
        }
        return out
    }

    /// Starts a new paragraph where you paused at the end of a sentence, so long
    /// monologues read like notes instead of one wall of text. Needs word timings.
    mutating func addParagraphs(minPause: Float = 1.0, minWords: Int = 15) {
        var sinceBreak = 0
        for i in words.indices.dropFirst() {
            sinceBreak += 1
            let previous = words[i - 1]
            // Parakeet stretches the last word before a silence across it, so its end can't be trusted.
            // Measuring from the word's start (minus a generous 0.6 s to say it) catches those pauses too.
            let pause = max(words[i].start - previous.end, words[i].start - previous.start - 0.6)
            let endsSentence = previous.text.last.map { ".?!".contains($0) } ?? false
            guard previous.end > 0 || words[i].start > 0 else { continue }
            if endsSentence && sinceBreak >= minWords && pause >= minPause {
                words[i].startsParagraph = true
                sinceBreak = 0
            }
        }
    }

    /// The match score, 0–100: the average of the word confidences.
    /// Each word's confidence is its weakest piece (see docs/match-score.md).
    var score: Int {
        guard !words.isEmpty else { return 0 }
        let mean = words.map(\.confidence).reduce(0, +) / Float(words.count)
        return Int((mean * 100).rounded())
    }

    /// Words below this are underlined as "worth a second look".
    static let shakyBelow: Float = 0.5

    var shakyCount: Int { words.filter { $0.confidence < Self.shakyBelow }.count }
}

enum ScoreTier {
    case high, moderate, low

    // Same cutoffs as Vox2's meaning check.
    init(_ score: Int) {
        switch score {
        case 85...: self = .high
        case 65..<85: self = .moderate
        default: self = .low
        }
    }

    var label: String {
        switch self {
        case .high: "high"
        case .moderate: "check"
        case .low: "low"
        }
    }
}
