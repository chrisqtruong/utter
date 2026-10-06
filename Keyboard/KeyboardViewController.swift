import UIKit
import AudioToolbox
import SwiftUI
import Observation

/// The Utter keyboard: a marker-dot mic, plus globe, space, delete and return.
/// Keyboards can't use the microphone, so the first tap opens the Utter app, which listens
/// in the background; after that the mic button starts and stops it from here, and the text
/// the app hears comes back through the shared App Group store to be typed.
final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    /// Lets key presses play the system click, when the person has keyboard clicks on.
    var enableInputClicksWhenVisible: Bool { true }
    private let tapFeel = UIImpactFeedbackGenerator(style: .light)
    private let micFeel = UIImpactFeedbackGenerator(style: .medium)

    private let model = KeyboardModel()
    private var changed: DarwinObserver?
    private var ackObserver: DarwinObserver?
    private var waitingForAck = false

    override func viewDidLoad() {
        super.viewDidLoad()
        model.hasFullAccess = hasFullAccess
        model.showGlobe = needsInputModeSwitchKey
        model.onMic = { [weak self] in self?.micFeel.impactOccurred(); AudioServicesPlaySystemSound(1520); self?.micTapped() }
        model.onType = { [weak self] text in self?.keyFeedback(); self?.textDocumentProxy.insertText(text) }
        model.onDelete = { [weak self] in self?.keyFeedback(); self?.textDocumentProxy.deleteBackward() }
        model.onGlobe = { [weak self] in self?.keyFeedback(); self?.advanceToNextInputMode() }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 246),
        ])
        host.didMove(toParent: self)

        changed = DarwinObserver(KeyboardLink.changed) { [weak self] in self?.refresh() }
        ackObserver = DarwinObserver(KeyboardLink.ack) { [weak self] in self?.waitingForAck = false }
        tapFeel.prepare(); micFeel.prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        refresh()
    }

    /// A light tap and the system click, like the regular keyboard. (Keyboards can only make
    /// haptics with Full Access on; the click follows the person's keyboard-clicks setting.)
    private func keyFeedback() {
        tapFeel.impactOccurred()
        AudioServicesPlaySystemSound(1519)   // the light "peek" tap; works in keyboards when UIKit's haptics don't
        UIDevice.current.playInputClick()
        tapFeel.prepare()
    }

    /// Reads what the app has shared, and types any new text it heard.
    private func refresh() {
        model.load()
        guard hasFullAccess else { return }
        let d = KeyboardLink.read()
        let mine = UserDefaults.standard   // the keyboard's own memory of what it already typed
        guard let id = d[KeyboardLink.Key.resultID] as? String,
              id != mine.string(forKey: KeyboardLink.Key.inserted),
              let text = d[KeyboardLink.Key.result] as? String else { return }
        mine.set(id, forKey: KeyboardLink.Key.inserted)
        // only type fresh results, so an old one never lands in the wrong place later
        let age = Date().timeIntervalSince1970 - (d[KeyboardLink.Key.resultAt] as? Double ?? 0)
        guard age < 120 else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let spacer = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") ? "" : " "
        textDocumentProxy.insertText(spacer + text)
    }

    /// Asks the app to start or stop. If it answers, stay here; if not (no session), open it.
    private func micTapped() {
        guard hasFullAccess else { model.note = "Turn on Allow Full Access first (see below)."; return }
        waitingForAck = true
        KeyboardLink.post(KeyboardLink.toggle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.waitingForAck else { return }
            self.waitingForAck = false
            self.openApp()
        }
    }

    /// Keyboards can't open apps through the normal API, so ask the app object up the responder chain.
    private func openApp() {
        let url = KeyboardLink.openURL as NSURL
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), NSStringFromClass(type(of: current)).contains("Application") {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: Open.self)
                open(current, selector, url, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        model.note = "Open the Utter app once, then come back."
    }
}

@Observable
final class KeyboardModel {
    var state: KeyboardLink.State = .off
    var note: String?
    var hasFullAccess = false
    var showGlobe = true
    var colors = ["#323437", "#e2b714", "#646669", "#2c2e31", "#d1d0c5", "#ca4754"]

    var onMic: () -> Void = {}
    var onType: (String) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onGlobe: () -> Void = {}

    func load() {
        let d = KeyboardLink.read()
        state = KeyboardLink.sessionAlive ? (KeyboardLink.State(rawValue: d[KeyboardLink.Key.state] as? String ?? "") ?? .off) : .off
        note = d[KeyboardLink.Key.note] as? String
        if let saved = d[KeyboardLink.Key.theme] as? [String], saved.count == 6 { colors = saved }
    }
}

struct KeyboardView: View {
    let model: KeyboardModel

    private var bg: Color { Color(hex: model.colors[0]) }
    private var main: Color { Color(hex: model.colors[1]) }
    private var sub: Color { Color(hex: model.colors[2]) }
    private var alt: Color { Color(hex: model.colors[3]) }
    private var text: Color { Color(hex: model.colors[4]) }
    private var error: Color { Color(hex: model.colors[5]) }

    private var status: String {
        if !model.hasFullAccess { return "allow full access to use utter" }
        if let note = model.note { return note.lowercased() }
        switch model.state {
        case .off: return "tap to talk"
        case .ready: return "tap to talk"
        case .listening: return "listening… tap when you’re done"
        case .writing: return "writing it down…"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(status)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(model.note != nil ? error : sub)
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            // the mic sits centered in the space between the status line and the keys
            Button(action: model.onMic) {
                ZStack {
                    MarkerDot().fill(Color.black.opacity(0.16)).offset(y: 3)
                    MarkerDot().fill(model.state == .listening ? error : main)
                    Image(systemName: model.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(bg)
                }
                .frame(width: 92, height: 92)
                .opacity(model.state == .writing ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(model.state == .writing)
            .accessibilityLabel(model.state == .listening ? "Stop dictating" : "Start dictating")

            if !model.hasFullAccess {
                Text("Settings → General → Keyboard → Keyboards → Utter → Allow Full Access")
                    .font(.system(size: 11)).foregroundStyle(sub)
                    .multilineTextAlignment(.center).padding(.horizontal, 16)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if model.showGlobe {
                    key(Image(systemName: "globe"), label: "Next keyboard", action: model.onGlobe)
                }
                Button { model.onType(" ") } label: {
                    Text("space").font(.system(size: 15, design: .monospaced)).foregroundStyle(text)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(alt, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                key(Image(systemName: "delete.left"), label: "Delete", action: model.onDelete)
                key(Image(systemName: "return"), label: "Return") { model.onType("\n") }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }

    private func key(_ icon: Image, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.font(.system(size: 17)).foregroundStyle(text)
                .frame(width: 52, height: 42)
                .background(alt, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
