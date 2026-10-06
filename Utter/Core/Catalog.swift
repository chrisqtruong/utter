import Foundation
import FluidAudio

/// The speech models Utter offers. Kept short on purpose: one fast pick,
/// one tiny pick, and three Whisper sizes for languages Parakeet doesn't cover.
struct SpeechModel: Identifiable, Hashable {
    enum Family: String { case parakeet, whisper }

    let id: String
    let name: String
    let family: Family
    /// Download size in MB, measured from the model files on Hugging Face (Oct 2026).
    let megabytes: Int
    let languages: String
    /// What it's good at, and what it costs. One short line each.
    let pro: String
    let con: String
    var recommended = false

    /// Whisper: the folder name in argmaxinc/whisperkit-coreml.
    var whisperVariant: String { id }

    var parakeetVersion: AsrModelVersion {
        id == "parakeet-110m" ? .tdtCtc110m : .v3
    }

    var sizeLabel: String { formatMB(Double(megabytes)) }
}

enum Catalog {
    static let models: [SpeechModel] = [
        SpeechModel(id: "parakeet-v3", name: "Parakeet v3", family: .parakeet, megabytes: 490,
                    languages: "English + 24 European languages",
                    pro: "very fast, very accurate in English, good punctuation",
                    con: "no Asian languages", recommended: true),
        SpeechModel(id: "parakeet-110m", name: "Parakeet Mini", family: .parakeet, megabytes: 230,
                    languages: "English",
                    pro: "smallest download, quickest to start",
                    con: "English only; more slips on names and fast talk"),
        SpeechModel(id: "openai_whisper-base", name: "Whisper Base", family: .whisper, megabytes: 150,
                    languages: "99 languages",
                    pro: "the lightest Whisper; quick to download and start",
                    con: "makes the most mistakes; can invent words in long silences"),
        SpeechModel(id: "openai_whisper-small", name: "Whisper Small", family: .whisper, megabytes: 490,
                    languages: "99 languages",
                    pro: "a solid middle ground for other languages and accents",
                    con: "slower than Parakeet; can invent words in long silences"),
        SpeechModel(id: "openai_whisper-large-v3-v20240930_626MB", name: "Whisper Large v3", family: .whisper, megabytes: 630,
                    languages: "99 languages",
                    pro: "most accurate for other languages and strong accents",
                    con: "slowest and biggest; uses more battery on long notes"),
    ]

    static func model(_ id: String?) -> SpeechModel? {
        models.first { $0.id == id }
    }
}

/// Languages offered for Whisper. Parakeet figures out the language by itself.
enum Languages {
    static let options: [(code: String, name: String)] = [
        ("auto", "Detect automatically"), ("en", "English"), ("vi", "Vietnamese"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("tl", "Tagalog"), ("pt", "Portuguese"), ("it", "Italian"), ("ar", "Arabic"), ("hi", "Hindi"),
    ]
}

func formatMB(_ mb: Double) -> String {
    if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
    if mb < 1 { return "\(max(1, Int((mb * 1000).rounded()))) KB" }   // small things, like notes
    return "\(Int(mb.rounded())) MB"
}

/// The app itself on disk (its code and the speech libraries), not counting models or notes.
let appSizeMB: Double = ModelStore.sizeMB(of: Bundle.main.bundleURL)
