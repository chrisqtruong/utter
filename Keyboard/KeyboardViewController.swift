import UIKit
import SwiftUI
import Observation

/// The Utter keyboard: a marker-dot mic, plus globe, space, delete and return.
/// Keyboards can't use the microphone, so the first tap opens the Utter app, which listens
/// in the background; after that the mic button starts and stops it from here, and the text
/// the app hears comes back through the shared App Group store to be typed.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var changed: DarwinObserver?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.hasFullAccess = hasFullAccess
        model.showGlobe = needsInputModeSwitchKey
        model.onMic = { [weak self] in self?.micTapped() }
        model.onType = { [weak self] text in self?.textDocumentProxy.insertText(text) }
        model.onDelete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.onGlobe = { [weak self] in self?.advanceToNextInputMode() }

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
            view.heightAnchor.constraint(equalToConstant: 236),
        ])
        host.didMove(toParent: self)

        changed = DarwinObserver(KeyboardLink.changed) { [weak self] in self?.refresh() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        refresh()
    }

    /// Reads what the app has shared, and types any new text it heard.
    private func refresh() {
        model.load()
        guard hasFullAccess, let store = KeyboardLink.store,
              let id = store.string(forKey: KeyboardLink.Key.resultID),
              id != store.string(forKey: KeyboardLink.Key.inserted),
              let text = store.string(forKey: KeyboardLink.Key.result) else { return }
        // only type fresh results, so an old one never lands in the wrong place later
        let age = Date().timeIntervalSince1970 - store.double(forKey: KeyboardLink.Key.resultAt)
        store.set(id, forKey: KeyboardLink.Key.inserted)
        guard age < 120 else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let spacer = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") ? "" : " "
        textDocumentProxy.insertText(spacer + text)
    }

    private func micTapped() {
        guard hasFullAccess else { model.note = "Turn on Allow Full Access first (see below)."; return }
        if KeyboardLink.sessionAlive {
            KeyboardLink.post(KeyboardLink.toggle)
        } else {
            openApp()
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
        guard let store = KeyboardLink.store else { return }
        state = KeyboardLink.sessionAlive ? KeyboardLink.state : .off
        note = store.string(forKey: KeyboardLink.Key.note)
        if let saved = store.stringArray(forKey: KeyboardLink.Key.theme), saved.count == 6 { colors = saved }
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
                .padding(.top, 12)
                .padding(.horizontal, 16)

            Button(action: model.onMic) {
                ZStack {
                    MarkerDot().fill(Color.black.opacity(0.16)).offset(y: 3)
                    MarkerDot().fill(model.state == .listening ? error : main)
                    Image(systemName: model.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(bg)
                }
                .frame(width: 78, height: 78)
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
