import Foundation
import Observation

/// The voice check: read a short passage and your names aloud once, and Utter
/// (1) finds which downloaded model gets your voice right most often,
/// (2) adds names it mishears to your dictionary, and
/// (3) tunes the match score so "85" means about 85% of your words are right.
/// The models themselves don't change; see docs/voice-check.md.
@Observable
final class VoiceProfile {
    struct ModelResult: Codable, Hashable {
        var id: String
        var name: String
        var accuracy: Double      // share of words right, 0–1
        var words: Int
    }

    /// One step of the score mapping: when the model said `said`, it was right `actual` of the time.
    struct Bin: Codable, Hashable {
        var said: Double
        var actual: Double
        var count: Int
    }

    struct Result: Codable {
        var date: Date
        var models: [ModelResult]
        var calibration: [String: [Bin]]   // by model id
        var mic: String
        var namesLearned: Int
    }

    private(set) var result: Result?
    /// The names you said last time, so the next check starts with them.
    var names: [String] = [] { didSet { persist() } }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("voice-check.json")
    }()

    private struct Saved: Codable { var result: Result?; var names: [String] }

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            result = saved.result
            names = saved.names
        }
    }

    func save(_ result: Result) {
        self.result = result
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Saved(result: result, names: names)) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// "today", "3 days ago", or nil if never run.
    var lastRunLabel: String? {
        guard let date = result?.date else { return nil }
        if Calendar.current.isDateInToday(date) { return "today" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }

    /// True once it's been a while (or the mic or room may have changed).
    var isStale: Bool {
        guard let date = result?.date else { return true }
        return Date().timeIntervalSince(date) > 90 * 24 * 3600
    }

    func isTuned(_ modelID: String) -> Bool { result?.calibration[modelID] != nil }

    // MARK: Tuning the score

    /// Replaces each word's raw confidence with how often this model was actually right
    /// at that confidence, for your voice, in your voice check.
    func calibrate(_ transcript: Transcript, modelID: String) -> Transcript {
        guard let bins = result?.calibration[modelID], !bins.isEmpty else { return transcript }
        var out = transcript
        for i in out.words.indices {
            out.words[i].confidence = Float(Self.map(Double(out.words[i].confidence), bins))
        }
        return out
    }

    /// Straight lines between the bins; flat beyond the ends.
    private static func map(_ x: Double, _ bins: [Bin]) -> Double {
        guard let first = bins.first, let last = bins.last else { return x }
        if x <= first.said { return first.actual }
        if x >= last.said { return last.actual }
        for (a, b) in zip(bins, bins.dropFirst()) where x <= b.said {
            let t = (x - a.said) / max(0.0001, b.said - a.said)
            return a.actual + t * (b.actual - a.actual)
        }
        return x
    }
}

// MARK: - Checking a recording

enum VoiceCheck {
    /// Written for Utter: everyday words and a mix of sounds, no numbers (models write "twenty" and "20" differently).
    static let passage = """
        Every morning I make a cup of coffee and look out the window before the day starts. \
        Some days the street is quiet, and other days the neighbors are already out walking their dogs. \
        I like to write down a few thoughts while they are still fresh: what I want to finish, \
        who I need to call, and anything that made me laugh yesterday. Later I might read them back \
        and wonder what I was thinking. My grandmother used to say that a short pencil is better than a long memory. \
        She was right about that, and about most things. When the weather is nice, I take the long way home \
        through the park, past the old library and the fruit stand on the corner, and I try not to check my phone.
        """

    struct ModelRun {
        var model: SpeechModel
        var accuracy: Double
        var words: Int
        var bins: [VoiceProfile.Bin]
        var names: [NameResult]
    }

    struct NameResult: Hashable {
        enum Outcome: Hashable { case right, fixable(heard: String), tooCommon(heard: String), missed }
        var name: String
        var outcome: Outcome
    }

    /// Compares what you read with what one model heard.
    static func score(_ heard: Transcript, model: SpeechModel, names: [String]) -> ModelRun {
        // The reference: the passage, then each name.
        var ref = tokens(passage)
        var nameRanges: [(String, Range<Int>)] = []
        for name in names {
            let t = tokens(name)
            guard !t.isEmpty else { continue }
            nameRanges.append((name, ref.count..<(ref.count + t.count)))
            ref += t
        }
        let hypWords = heard.words.filter { !norm($0.text).isEmpty }
        let hyp = hypWords.map { norm($0.text) }
        let ops = align(ref, hyp)

        // Word accuracy, the usual way: 1 − (substitutions + deletions + insertions) / words read.
        let errors = ops.filter { if case .match = $0 { false } else { true } }.count
        let accuracy = max(0, 1 - Double(errors) / Double(max(1, ref.count)))

        // Which heard words were right, for the score mapping.
        var labeled: [(conf: Double, right: Bool)] = []
        for op in ops {
            switch op {
            case .match(_, let h): labeled.append((Double(hypWords[h].confidence), true))
            case .sub(_, let h), .ins(let h): labeled.append((Double(hypWords[h].confidence), false))
            case .del: break
            }
        }

        // What each name came out as.
        let common = commonWords.union(ref.prefix(tokens(passage).count))
        var results: [NameResult] = []
        for (name, range) in nameRanges {
            var heardWords: [String] = []
            var lastRef = -1
            for op in ops {
                switch op {
                case .match(let r, let h), .sub(let r, let h):
                    lastRef = r
                    if range.contains(r) { heardWords.append(hypWords[h].text) }
                case .del(let r): lastRef = r
                case .ins(let h):
                    // an extra word in the middle of a name belongs to it ("Fells" "point" "e")
                    if lastRef >= range.lowerBound && lastRef < range.upperBound - 1 { heardWords.append(hypWords[h].text) }
                }
            }
            let heardText = heardWords.map { $0.trimmingCharacters(in: .punctuationCharacters) }.joined(separator: " ")
            let outcome: NameResult.Outcome
            if heardText.isEmpty { outcome = .missed }
            else if tokens(heardText) == tokens(name) { outcome = .right }
            else if tokens(heardText).allSatisfy({ common.contains($0) }) { outcome = .tooCommon(heard: heardText) }
            else { outcome = .fixable(heard: heardText) }
            results.append(NameResult(name: name, outcome: outcome))
        }

        return ModelRun(model: model, accuracy: accuracy, words: ref.count, bins: bins(labeled), names: results)
    }

    /// Groups words by how sure the model was, and how often it was right in each group.
    /// Small groups lean on the model's own number, and the result never goes down as confidence goes up.
    private static func bins(_ labeled: [(conf: Double, right: Bool)]) -> [VoiceProfile.Bin] {
        let edges: [Double] = [0, 0.5, 0.7, 0.85, 0.95, 1.01]
        var out: [VoiceProfile.Bin] = []
        for (lo, hi) in zip(edges, edges.dropFirst()) {
            let group = labeled.filter { $0.conf >= lo && $0.conf < hi }
            guard !group.isEmpty else { continue }
            let said = group.map(\.conf).reduce(0, +) / Double(group.count)
            let right = Double(group.filter(\.right).count)
            let prior = 5.0   // as if we'd also seen 5 words where the model was exactly as right as it claimed
            out.append(VoiceProfile.Bin(said: said, actual: (right + prior * said) / (Double(group.count) + prior), count: group.count))
        }
        // never let a higher confidence map to a lower score
        for i in out.indices.dropFirst() where out[i].actual < out[i - 1].actual {
            let pooled = (out[i].actual * Double(out[i].count) + out[i - 1].actual * Double(out[i - 1].count)) / Double(out[i].count + out[i - 1].count)
            out[i].actual = pooled; out[i - 1].actual = pooled
        }
        return out
    }

    /// Is the room quiet enough and are you loud enough? Measured in 100 ms slices.
    static func micVerdict(_ samples: [Float]) -> String {
        let frame = 1_600
        var levels: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for s in samples[i..<(i + frame)] { sum += s * s }
            levels.append((sum / Float(frame)).squareRoot())
            i += frame
        }
        guard levels.count > 10 else { return "Too short to tell." }
        let sorted = levels.sorted()
        let noise = max(0.0001, sorted[sorted.count / 10])        // quietest moments: the room
        let voice = sorted[sorted.count * 9 / 10]                  // loudest moments: you
        let snr = 20 * log10(Double(voice / noise))
        if voice < 0.01 { return "You were a little quiet. Hold the phone a bit closer." }
        if snr < 15 { return "The room was noisy. Somewhere quieter will help a lot." }
        return "Sounds good: clear voice, quiet room."
    }

    // MARK: Word alignment (edit distance)

    enum Op { case match(Int, Int), sub(Int, Int), ins(Int), del(Int) }

    /// Lines up what you read with what was heard, with the fewest changes.
    static func align(_ ref: [String], _ hyp: [String]) -> [Op] {
        let n = ref.count, m = hyp.count
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j - 1] + cost, d[i - 1][j] + 1, d[i][j - 1] + 1)
                }
            }
        }
        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1) {
                ops.append(ref[i - 1] == hyp[j - 1] ? .match(i - 1, j - 1) : .sub(i - 1, j - 1)); i -= 1; j -= 1
            } else if i > 0 && d[i][j] == d[i - 1][j] + 1 {
                ops.append(.del(i - 1)); i -= 1
            } else {
                ops.append(.ins(j - 1)); j -= 1
            }
        }
        return ops.reversed()
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { norm(String($0)) }.filter { !$0.isEmpty }
    }

    static func norm(_ word: String) -> String {
        word.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Too common to rewrite automatically: a name heard as "one" mustn't turn every "one" into that name.
    static let commonWords: Set<String> = Set("""
        a about after again all also am an and any are as at be because been before being but by can come could day did do does \
        down even for from get go going good got had has have he her here him his how i if in into is it its just know like look \
        make man many me more most my new no not now of off oh ok okay on one only or other our out over people really right said \
        say see she so some take than that the their them then there these they thing think this time to too two up us very want \
        was way we well went were what when where which who why will with won would yeah year yes you your one two three four \
        five six seven eight nine ten long son sun
        """.split(whereSeparator: \.isWhitespace).map(String.init))
}
