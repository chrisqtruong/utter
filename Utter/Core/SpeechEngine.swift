import Foundation
import FluidAudio
import WhisperKit

/// Holds the one loaded speech model and turns audio into a scored transcript.
/// An actor, so the heavy work stays off the main thread.
actor SpeechEngine {
    private var whisper: WhisperKit?
    private var parakeet: AsrManager?
    private(set) var loadedID: String?

    static let whisperBase: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func whisperFolder(_ model: SpeechModel) -> URL {
        whisperBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.whisperVariant)", isDirectory: true)
    }

    static func parakeetFolder(_ model: SpeechModel) -> URL {
        AsrModels.defaultCacheDirectory(for: model.parakeetVersion)
    }

    // MARK: Loading

    func load(_ model: SpeechModel) async throws {
        if loadedID == model.id { return }
        let started = Date()
        await unload()
        switch model.family {
        case .whisper:
            let config = WhisperKitConfig(
                model: model.whisperVariant,
                downloadBase: Self.whisperBase,
                modelFolder: Self.whisperFolder(model).path,
                tokenizerFolder: Self.whisperBase,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            whisper = try await WhisperKit(config)
        case .parakeet:
            let version = model.parakeetVersion
            let models = try await AsrModels.load(from: Self.parakeetFolder(model), version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            parakeet = manager
        }
        loadedID = model.id
        let loaded = Date()
        // A tiny silent practice run: the first real transcription after loading would otherwise
        // pay a one-time setup cost on the phone's AI chip.
        _ = try? await transcribe([Float](repeating: 0, count: 16_000), language: "en")
        print("UTTER_TIMING load \(model.id): \(String(format: "%.1f", loaded.timeIntervalSince(started)))s, warm-up \(String(format: "%.1f", Date().timeIntervalSince(loaded)))s")
    }

    func unload() async {
        if let parakeet { await parakeet.cleanup() }
        whisper = nil
        parakeet = nil
        loadedID = nil
    }

    // MARK: Transcribing

    /// - Parameter samples: 16 kHz mono audio.
    /// - Parameter hints: words to spell your way; Whisper reads them as a prompt.
    func transcribe(_ samples: [Float], language: String, hints: [String] = []) async throws -> Transcript {
        if let whisper {
            return try await transcribeWhisper(whisper, samples, language: language, hints: hints)
        }
        if let parakeet, let model = Catalog.model(loadedID) {
            return try await transcribeParakeet(parakeet, samples, version: model.parakeetVersion)
        }
        throw UtterError.noModel
    }

    private func transcribeWhisper(_ kit: WhisperKit, _ samples: [Float], language: String, hints: [String]) async throws -> Transcript {
        let auto = language == "auto"
        // Your dictionary words as a prompt nudge Whisper toward your spellings ("Vox2", "Fells Point").
        var prompt: [Int]?
        if !hints.isEmpty, let tokenizer = kit.tokenizer {
            prompt = tokenizer.encode(text: " " + hints.joined(separator: ", "))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        var options = DecodingOptions(
            task: .transcribe,
            language: auto ? nil : language,
            temperatureFallbackCount: 3,
            detectLanguage: auto,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        options.promptTokens = prompt
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        var words: [ScoredWord] = []
        for segment in results.flatMap(\.segments) {
            if let timed = segment.words, !timed.isEmpty {
                words += timed.map {
                    ScoredWord(text: $0.word.trimmingCharacters(in: .whitespaces), confidence: $0.probability, start: $0.start, end: $0.end)
                }
            } else {
                // No word timings: give every word the segment's average token probability,
                // and the segment's start and end, so paragraphs can still break between segments.
                let confidence = Float(exp(Double(segment.avgLogprob)))
                words += Self.split(segment.text).map { ScoredWord(text: $0, confidence: confidence, start: segment.start, end: segment.end) }
            }
        }
        var transcript = Transcript(words: words.filter { !$0.text.isEmpty })
        transcript.addParagraphs()
        return transcript
    }

    private func transcribeParakeet(_ manager: AsrManager, _ samples: [Float], version: AsrModelVersion) async throws -> Transcript {
        // Parakeet wants at least a second of audio; pad short clips with silence.
        var audio = samples
        if audio.count < 16_000 { audio += [Float](repeating: 0, count: 16_000 - audio.count) }

        var state = try TdtDecoderState(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(audio, decoderState: &state)

        guard let tokens = result.tokenTimings, !tokens.isEmpty else {
            return Transcript(words: Self.split(result.text).map { ScoredWord(text: $0, confidence: result.confidence) })
        }
        // Tokens are word pieces; a leading space starts a new word.
        // A word is only as sure as its least sure piece.
        var words: [ScoredWord] = []
        for token in tokens {
            let piece = token.token
            if piece.hasPrefix(" ") || words.isEmpty {
                let text = piece.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { continue }
                words.append(ScoredWord(text: text, confidence: token.confidence,
                                        start: Float(token.startTime), end: Float(token.endTime)))
            } else {
                words[words.count - 1].text += piece
                words[words.count - 1].confidence = min(words[words.count - 1].confidence, token.confidence)
                words[words.count - 1].end = Float(token.endTime)
            }
        }
        var transcript = Transcript(words: words)
        transcript.addParagraphs()
        return transcript
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

enum UtterError: LocalizedError {
    case noModel, micDenied, micUnavailable

    var errorDescription: String? {
        switch self {
        case .noModel: "Pick a speech model first."
        case .micDenied: "Utter needs the microphone. Turn it on in Settings → Apps → Utter."
        case .micUnavailable: "The microphone isn't available right now."
        }
    }
}
