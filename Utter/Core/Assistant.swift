import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional writing help from Apple's on-device model (Apple Intelligence, iOS 26+).
/// It runs on the iPhone itself: no download, no account, nothing leaves the phone.
/// On phones without Apple Intelligence these features simply don't show up.
enum Assistant {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Why it's off, in plain words, for Settings.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in iPhone Settings to use these."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready on this iPhone. Try again later."
            default: return "This iPhone doesn't support Apple Intelligence."
            }
        }
        #endif
        return "Needs iOS 26 or later with Apple Intelligence."
    }

    /// A few words naming what a note is about, for history.
    static func title(for text: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You name voice notes. Reply with only a short title of 2 to 6 words that says what the note is about. \
            No quotes, no ending punctuation, no emoji. Use the note's own language.
            """)
        // The opening is plenty to name a note, and keeps long ones inside the model's limit.
        let opening = String(text.prefix(1_500))
        guard let reply = try? await session.respond(to: opening) else { return nil }
        let title = reply.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.#*"))
        return title.isEmpty || title.count > 60 ? nil : title
        #else
        return nil
        #endif
    }

    /// Tidies a transcript: fixes punctuation and casing, drops false starts and repeated words,
    /// and keeps your words and meaning. Long notes go paragraph by paragraph so each piece fits the model.
    /// - Parameter spellings: words from your dictionary, kept exactly as written.
    static func tidy(_ text: String, spellings: [String] = []) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { throw AssistantError.unavailable }
        var out = ""
        for piece in chunks(of: text) {
            // A fresh session per piece, so earlier pieces don't crowd the context.
            let session = LanguageModelSession(instructions: """
                You clean up dictated text in one careful pass. \
                Fix punctuation and capitalization, and split run-on sentences into proper sentences. \
                Fix obvious speech-to-text slips. Remove false starts, stutters, and accidentally repeated words or phrases. \
                Keep the speaker's own words, tone, order and meaning. Do not summarize, rephrase for style, add anything, or answer questions in the text. \
                Keep paragraph breaks.\(spellings.isEmpty ? "" : " Always spell these exactly as written: " + spellings.joined(separator: ", ") + ".") \
                Reply with only the cleaned text.
                """)
            let reply = try await session.respond(to: piece.text)
            if !out.isEmpty { out += piece.joiner }
            out += reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
        #else
        throw AssistantError.unavailable
        #endif
    }

    /// Groups paragraphs into pieces of about 500 words (well inside the on-device model's limit).
    /// A paragraph longer than that is split between sentences. `joiner` is what goes back before each piece.
    private static func chunks(of text: String) -> [(text: String, joiner: String)] {
        var pieces: [(text: String, joiner: String)] = []
        var current: [String] = [], count = 0
        func flush() {
            if !current.isEmpty { pieces.append((current.joined(separator: "\n\n"), "\n\n")); current = []; count = 0 }
        }
        for paragraph in text.components(separatedBy: "\n\n") where !paragraph.isEmpty {
            let words = paragraph.split(separator: " ").count
            if words > 500 {
                flush()
                var group: [String] = [], groupCount = 0, first = true
                paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
                    guard let sentence else { return }
                    let n = sentence.split(separator: " ").count
                    if groupCount + n > 400, !group.isEmpty {
                        pieces.append((group.joined().trimmingCharacters(in: .whitespaces), first ? "\n\n" : " "))
                        group = []; groupCount = 0; first = false
                    }
                    group.append(sentence); groupCount += n
                }
                if !group.isEmpty { pieces.append((group.joined().trimmingCharacters(in: .whitespaces), first ? "\n\n" : " ")) }
                continue
            }
            if count + words > 500 { flush() }
            current.append(paragraph); count += words
        }
        flush()
        return pieces
    }
}

enum AssistantError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Intelligence isn't available on this iPhone." }
}
