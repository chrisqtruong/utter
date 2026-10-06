import Foundation
import Observation

/// The app's side of the Utter keyboard. When the keyboard opens the app (utter://keyboard),
/// the app turns the mic on and keeps it on in the background for a while: a "session".
/// During a session the keyboard's mic button starts and stops listening without leaving
/// the app you're typing in, and the text comes back to the keyboard to type.
@MainActor
@Observable
final class KeyboardSession {
    private(set) var active = false
    private(set) var state: KeyboardLink.State = .off
    /// True right after the keyboard opened the app, until you leave: home shows the way back.
    private(set) var showBackHint = false

    /// The mic stays on (keeping nothing) this long after a dictation, so the keyboard can start
    /// the next one without opening the app: iOS only lets an app turn the mic on while it's on screen.
    static let idleTimeout: TimeInterval = 2 * 60

    private let recorder = Recorder()
    private let dictator: Dictator
    private var heartbeat: Timer?
    private var lastUse = Date()
    private var toggleObserver: DarwinObserver?

    init(dictator: Dictator) {
        self.dictator = dictator
        toggleObserver = DarwinObserver(KeyboardLink.toggle) { [weak self] in
            Task { @MainActor in
                KeyboardLink.log("app", "toggle received, active=\(self?.active ?? false) state=\(self?.state.rawValue ?? "-")")
                guard let self, self.active else { return }
                KeyboardLink.post(KeyboardLink.ack)   // "got it": the keyboard stays where it is
                self.toggle()
            }
        }
        recorder.onMustStop = { [weak self] _ in
            Task { @MainActor in self?.end() }   // a call or another app took the mic
        }
        set(.off)
    }

    /// The keyboard opened the app: start a session and start listening right away.
    func startFromKeyboard() {
        KeyboardLink.log("app", "opened from keyboard, active=\(active) state=\(state.rawValue)")
        showBackHint = true
        Task {
            guard await Recorder.requestPermission() else { note("Utter needs the microphone. Turn it on in Settings → Apps → Utter."); return }
            if !active {
                do { try recorder.startStandby() } catch { note("The microphone isn't available right now."); return }
                active = true
                startHeartbeat()
            }
            // Opened while already listening: if listening only just started, this is the same tap
            // arriving twice (the app's reply reached the keyboard late), so keep listening.
            // Otherwise treat it as stop; the text is typed when you go back to the keyboard.
            if state == .listening {
                if Date().timeIntervalSince(lastUse) > 2.5 { await finish() }
            } else if state != .writing {
                beginCapture()
            }
        }
    }

    /// From the keyboard's mic button, during a session.
    func toggle() {
        guard active else { return }
        switch state {
        case .ready: beginCapture()
        case .listening: Task { await finish() }
        default: break
        }
    }

    /// You went back to the other app (or anywhere else).
    func leftApp() { showBackHint = false }

    func end() {
        showBackHint = false
        heartbeat?.invalidate(); heartbeat = nil
        if active { _ = recorder.stop() }
        active = false
        KeyboardLink.write([KeyboardLink.Key.alive: 0.0])
        set(.off)
    }

    // MARK: Steps

    private func beginCapture() {
        recorder.beginCapture()
        lastUse = Date()
        note(nil)
        set(.listening)
    }

    private func finish() async {
        let samples = recorder.endCapture()
        set(.writing)
        lastUse = Date()
        KeyboardLink.log("app", "finish: \(samples.count / 16_000)s of audio")
        if let text = await dictator.transcribeForKeyboard(samples) {
            KeyboardLink.write([KeyboardLink.Key.result: text,
                                KeyboardLink.Key.resultID: UUID().uuidString,
                                KeyboardLink.Key.resultAt: Date().timeIntervalSince1970,
                                KeyboardLink.Key.note: nil])
            KeyboardLink.log("app", "result saved (\(text.count) chars), resultID=\(String(describing: KeyboardLink.read()[KeyboardLink.Key.resultID] ?? "-").prefix(8))")
            KeyboardLink.post(KeyboardLink.changed)
        } else {
            note("Didn't hear any talking.")
        }
        lastUse = Date()
        set(.ready)
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let beat = { [weak self] in
            guard let self else { return }
            KeyboardLink.write([KeyboardLink.Key.alive: Date().timeIntervalSince1970])
            if self.state == .ready, Date().timeIntervalSince(self.lastUse) > Self.idleTimeout { self.end() }
        }
        beat()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in Task { @MainActor in beat() } }
    }

    private func note(_ text: String?) {
        KeyboardLink.write([KeyboardLink.Key.note: text])
        KeyboardLink.post(KeyboardLink.changed)
    }

    private func set(_ new: KeyboardLink.State) {
        state = new
        KeyboardLink.write([KeyboardLink.Key.state: new.rawValue])
        KeyboardLink.post(KeyboardLink.changed)
    }
}
