import Foundation
import Observation

/// A saved dictation. Text and scores only: the audio is never kept.
struct Dictation: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var transcript: Transcript
    var modelName: String
    var seconds: Double
    /// Set once you edit the text. The original words and their scores are kept alongside.
    var editedText: String?
    /// A short name from the on-device model, when Apple Intelligence is on.
    var title: String?
    /// Where it came from when it wasn't the mic: a file name, or "phone audio".
    var source: String?

    /// Earlier versions, newest last, for undo. `nil` stands for the original transcription.
    var undoStack: [String?]?

    var text: String { editedText ?? transcript.text }
    var isEdited: Bool { editedText != nil }
    var canUndo: Bool { !(undoStack ?? []).isEmpty }
    /// How deep the undo stack was right after tidy. Tidy is a one-time pass; undoing back past it offers it again.
    var tidyDepth: Int?
    var isTidied: Bool { tidyDepth != nil }
    /// What tidy would make of the current text, worked out ahead of time. Nil until checked.
    var tidySuggestion: String?
    /// The text the suggestion was made from, so an edit makes it stale.
    var tidyCheckedText: String?
    /// True when tidy was checked for this exact text.
    var tidyChecked: Bool { tidyCheckedText == text }
    /// Show the tidy button only when tidy would actually change something.
    var canTidy: Bool { !isTidied && tidyChecked && tidySuggestion != nil }
    /// Set once "tidy automatically" has had its one go at this note, so undoing back to what
    /// you said doesn't tidy it again.
    var autoTidyDone: Bool?
    /// True when "tidy automatically" made the current tidy (not a tap).
    var autoTidied: Bool?
    /// The text is exactly what tidy made, with no edits since.
    var isJustTidied: Bool { isTidied && (undoStack?.count ?? 0) == tidyDepth }
    /// For the score line: what happened to the words since you said them.
    var changeLabel: String? {
        if isJustTidied { return autoTidied == true ? "auto-tidied" : "tidied" }
        return isEdited ? "edited" : nil
    }
}

/// The history, kept as one small JSON file in the app's private folder.
@Observable
final class History {
    private(set) var items: [Dictation] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Dictation].self, from: data) {
            items = saved
        }
    }

    func add(_ dictation: Dictation) {
        items.insert(dictation, at: 0)
        save()
    }

    /// Saves an edit. Editing back to exactly what was heard clears the edit.
    @discardableResult
    func edit(_ id: UUID, to text: String) -> Dictation? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let next: String? = trimmed == items[i].transcript.text ? nil : trimmed
        guard next != items[i].editedText else { return items[i] }   // nothing changed
        var stack = items[i].undoStack ?? []
        stack.append(items[i].editedText)
        items[i].undoStack = Array(stack.suffix(50))
        items[i].editedText = next
        save()
        return items[i]
    }

    /// Steps back one change. Repeat until it's the original transcription again.
    @discardableResult
    func undo(_ id: UUID) -> Dictation? {
        guard let i = items.firstIndex(where: { $0.id == id }), var stack = items[i].undoStack, !stack.isEmpty else { return nil }
        items[i].editedText = stack.removeLast()
        items[i].undoStack = stack
        if let depth = items[i].tidyDepth, stack.count < depth { items[i].tidyDepth = nil }
        save()
        return items[i]
    }

    /// Saves the tidied text as an edit and remembers that this note has been tidied.
    @discardableResult
    func applyTidy(_ id: UUID, text: String) -> Dictation? {
        guard edit(id, to: text) != nil, let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[i].tidyDepth = items[i].undoStack?.count ?? 0
        save()
        return items[i]
    }

    /// Records what tidy would do for the note's current text (nil suggestion: no change needed).
    @discardableResult
    func setTidyCheck(_ id: UUID, from text: String, suggestion: String?) -> Dictation? {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].text == text else { return nil }
        items[i].tidyCheckedText = text
        items[i].tidySuggestion = suggestion
        save()
        return items[i]
    }

    func markAutoTidied(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].autoTidied = true
        save()
    }

    func markAutoTidyDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].autoTidyDone = true
        save()
    }

    func setTitle(_ id: UUID, _ title: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = title
        save()
    }

    func delete(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    /// Removes notes older than this many days. Returns how many went.
    @discardableResult
    func delete(olderThanDays days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let before = items.count
        items.removeAll { $0.date < cutoff }
        if items.count != before { save() }
        return before - items.count
    }

    func count(olderThanDays days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return items.filter { $0.date < cutoff }.count
    }

    /// The "keep notes for" setting, applied when the app opens. 0 means forever.
    func applyKeepLimit() {
        let days = UserDefaults.standard.integer(forKey: "keepDays")
        if days > 0 { delete(olderThanDays: days) }
    }

    /// Size of the history file on disk, in MB.
    var diskMB: Double {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(bytes) / 1_000_000
    }

    func clear() {
        items = []
        save()
    }

    var totalWords: Int { items.reduce(0) { $0 + $1.transcript.words.count } }

    private let saveQueue = DispatchQueue(label: "history-save", qos: .utility)

    /// Writes in the background so a long history never stalls the screen.
    private func save() {
        let snapshot = items, url = url
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    #if DEBUG
    /// Sample notes for screenshots (`-seedDemo`). Replaces the current history.
    func seedDemo() {
        let samples: [(title: String?, text: String, sure: Float, model: String, minutesAgo: Double)] = [
            ("weekend trip ideas", "Thinking about a short trip this weekend. Somewhere with a good bookstore, a long walk by the water, and a place that does a proper breakfast. Leave Saturday morning, back Sunday night.", 0.96, "Parakeet v3", 25),
            (nil, "Pick up oat milk, coffee filters, and the good bread on the way home.", 0.98, "Parakeet v3", 95),
            ("photo series", "The waterfront at golden hour would make a great photo series. Try the 35 millimeter and shoot the same corner every evening for a week.", 0.84, "Parakeet v3", 240),
            ("newsletter idea", "Idea for the newsletter: a contact sheet of the week, one frame per day, with a single sentence under each.", 0.97, "Whisper Small", 1500),
            (nil, "Call the dentist to move Thursday's appointment, and reply to Sam about dinner.", 0.9, "Parakeet v3", 2900),
        ]
        items = samples.map { sample in
            let words = sample.text.split(separator: " ").enumerated().map { j, w in
                ScoredWord(text: String(w), confidence: j % 9 == 4 ? sample.sure - 0.38 : min(1, sample.sure + 0.03))
            }
            var d = Dictation(date: Date().addingTimeInterval(-sample.minutesAgo * 60),
                              transcript: Transcript(words: words), modelName: sample.model,
                              seconds: Double(words.count) / 2.6)
            d.title = sample.title
            return d
        }
        save()
    }
    #endif
}
