import SwiftUI
import Observation
import AVFoundation

/// The tap-to-talk loop: record → transcribe → tidy → copy → save to history.
@MainActor
@Observable
final class Dictator {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case transcribing
    }

    private(set) var phase: Phase = .idle
    private(set) var level: Float = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 40)
    private(set) var latest: Dictation?
    private(set) var copiedID: UUID?
    private(set) var tidyingID: UUID?
    /// After you fix one word, Utter offers to remember it.
    var suggestedFix: (heard: String, write: String)?
    var message: String?
    var showModelPicker = false

    private let recorder = Recorder()
    private let models: ModelStore
    private let history: History
    private let vocabulary: Vocabulary
    private let voice: VoiceProfile
    private var pendingStart = false
    private var warnedNearLimit = false

    init(models: ModelStore, history: History, vocabulary: Vocabulary, voice: VoiceProfile) {
        self.models = models
        self.history = history
        self.vocabulary = vocabulary
        self.voice = voice
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in self?.push(level: value) }
        }
        recorder.onMustStop = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                await self.stop()
                self.message = reason
            }
        }
    }

    var isRecording: Bool { if case .recording = phase { true } else { false } }

    func toggle() {
        switch phase {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        case .transcribing: break
        }
    }

    /// Seconds left before the 30-minute limit, while recording.
    func secondsLeft(at now: Date) -> Double? {
        guard case .recording(let since) = phase else { return nil }
        return Recorder.maxSeconds - now.timeIntervalSince(since)
    }

    /// From the Action button / Shortcut. If the app is still opening, start once it's on screen.
    func toggleFromShortcut() {
        if UIApplication.shared.applicationState == .active { toggle() } else { pendingStart = true }
    }

    func appBecameActive() {
        guard pendingStart else { return }
        pendingStart = false
        if phase == .idle { Task { await start() } }
    }

    /// Recording keeps going when the screen locks or you switch apps (background audio),
    /// so nothing happens here. If iOS ends the session anyway, the interruption handler saves what was said.
    func appWentToBackground() {}

    func clearLatest() { latest = nil; suggestedFix = nil }

    func undo(_ dictation: Dictation) {
        guard let updated = history.undo(dictation.id) else { return }
        suggestedFix = nil
        if latest?.id == dictation.id {
            latest = updated
            if UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true { copy(updated) }
        }
        Haptics.tap()
    }

    func rememberSuggestedFix() {
        if let fix = suggestedFix { vocabulary.save(heard: fix.heard, write: fix.write) }
        suggestedFix = nil
    }

    /// Notes of a couple of sentences or more get a short title, if Apple Intelligence is on.
    private func nameIfLong(_ dictation: Dictation) {
        let wanted = UserDefaults.standard.object(forKey: "aiTitles") as? Bool ?? true
        guard wanted, dictation.transcript.words.count >= 25, Assistant.isAvailable else { return }
        Task {
            guard let title = await Assistant.title(for: dictation.text) else { return }
            history.setTitle(dictation.id, title)
            if latest?.id == dictation.id { latest?.title = title }
        }
    }

    /// Cleans up a dictation with the on-device model. Saved as an edit, so "back to what you said" undoes it.
    func tidy(_ dictation: Dictation) async {
        guard !dictation.isTidied else { return }
        tidyingID = dictation.id
        defer { tidyingID = nil }
        do {
            let tidied = try await Assistant.tidy(dictation.text, spellings: vocabulary.hintWords)
            guard let updated = history.applyTidy(dictation.id, text: tidied) else { return }
            if latest?.id == dictation.id {
                latest = updated
                if UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true { copy(updated) }
            }
        } catch {
            message = "Couldn't tidy this one. Your text is unchanged."
        }
    }

    /// Saves an edit to the latest dictation and re-copies it if auto-copy is on.
    func saveEdit(_ text: String) {
        guard let latest else { return }
        suggestedFix = Vocabulary.singleWordFix(from: latest.text, to: text)
            .flatMap { fix in vocabulary.entries.contains { $0.heard.lowercased() == fix.heard.lowercased() } ? nil : fix }
        guard let updated = history.edit(latest.id, to: text) else { return }
        self.latest = updated
        if UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true { copy(updated) }
    }

    func copy(_ dictation: Dictation) {
        UIPasteboard.general.string = dictation.text
        copiedID = dictation.id
        Haptics.tap()
    }

    // MARK: Steps

    private func start() async {
        message = nil
        guard models.selectedIsReady else { showModelPicker = true; return }
        guard await Recorder.requestPermission() else { message = UtterError.micDenied.errorDescription; return }
        do {
            try recorder.start()
            levels = Array(repeating: 0, count: levels.count)
            phase = .recording(since: Date())
            warnedNearLimit = false
            Haptics.start()
            // Warm the model while you talk, in case it isn't loaded yet.
            Task { await models.loadSelected() }
        } catch {
            message = UtterError.micUnavailable.errorDescription
        }
    }

    private func stop() async {
        guard case .recording(let since) = phase else { return }
        let (samples, _) = recorder.stop()
        Haptics.stop()
        let seconds = Date().timeIntervalSince(since)
        // An accidental tap, or nothing but room noise: say so right away, without waiting on the model.
        guard seconds >= 0.6, SpeechCheck.hasSpeech(samples) else {
            phase = .idle
            message = seconds < 0.6 ? "Tap once to start, again to stop." : "Didn't hear any talking, so nothing was saved."
            return
        }
        await process(samples, seconds: seconds)
    }

    // MARK: Files and phone audio

    /// Transcribes an audio or video file: picked in Utter, or shared to it from another app.
    func transcribeFile(_ url: URL) async {
        guard phase == .idle else { return }
        guard models.selectedIsReady else { showModelPicker = true; return }
        message = nil
        phase = .transcribing
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            // files shared in from other apps land in Utter's Inbox as a copy; don't keep it
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        do {
            let loaded = try await AudioImport.load(url)
            await process(loaded.samples, seconds: loaded.seconds, source: url.lastPathComponent)
            if loaded.trimmed { message = "That file is over an hour, so only the first hour was turned into text." }
        } catch {
            phase = .idle
            message = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
        }
    }

    /// Turns finished phone-audio captures (from screen recording mode) into notes, then deletes them.
    func processCaptures() async {
        guard phase == .idle, models.selectedIsReady else { return }
        for url in CaptureInbox.waiting() {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let samples = try? AudioImport.loadRaw(url), SpeechCheck.hasSpeech(samples) else { continue }
            await process(samples, seconds: Double(samples.count) / 16_000, source: "phone audio")
        }
    }

    private func process(_ samples: [Float], seconds: Double, source: String? = nil) async {
        phase = .transcribing
        // If the phone is locked, ask iOS for time to finish turning it into text.
        let background = UIApplication.shared.beginBackgroundTask()
        defer {
            phase = .idle
            UIApplication.shared.endBackgroundTask(background)
        }

        await models.loadSelected()
        guard let model = models.selected else { return }
        do {
            let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
            // Scores tuned to your voice, if you've run a voice check with this model.
            let transcribeStart = Date()
            let raw = voice.calibrate(try await models.engine.transcribe(samples, language: language, hints: vocabulary.hintWords),
                                      modelID: model.id)
            print("UTTER_TIMING transcribe \(String(format: "%.1f", seconds))s of audio in \(String(format: "%.1f", Date().timeIntervalSince(transcribeStart)))s")
            let removeFillers = UserDefaults.standard.object(forKey: "removeFillers") as? Bool ?? true
            let transcript = vocabulary.apply(to: Cleanup.apply(raw, removeFillers: removeFillers))
            guard !transcript.words.isEmpty else { message = "Didn't catch any words. Try again a little closer."; return }

            var dictation = Dictation(transcript: transcript, modelName: model.name, seconds: seconds)
            dictation.source = source
            history.add(dictation)
            latest = dictation
            suggestedFix = nil
            if UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true { copy(dictation) }
            nameIfLong(dictation)
        } catch {
            message = "Something went wrong turning that into text. Try again."
        }
    }

    #if DEBUG
    /// Testing without a voice: `-testFile /path/to/audio` runs a file through the same steps.
    func runTestFileIfAsked() async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-testFile"), i + 1 < args.count else { return }
        await models.loadSelected()
        let started = Date()
        // the same path as "a file" and the share sheet
        await transcribeFile(URL(fileURLWithPath: args[i + 1]))
        print("UTTER_TEST took \(Date().timeIntervalSince(started))s score \(latest?.transcript.score ?? -1) source \(latest?.source ?? "-"): \(latest?.text ?? message ?? "")")
    }
    #endif

    private func push(level value: Float) {
        guard isRecording else { return }
        // One buzz with a minute to go, so a long take never ends by surprise.
        if !warnedNearLimit, let left = secondsLeft(at: Date()), left <= 60 {
            warnedNearLimit = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        level = value
        levels.removeFirst()
        levels.append(value)
    }
}

enum Haptics {
    static func start() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func stop() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
