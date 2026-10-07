import UIKit
import AudioToolbox

/// The Utter keyboard: a full set of keys for quick fixes, plus a marker-dot mic.
/// Keyboards can't use the microphone, so the first mic tap opens the Utter app, which listens
/// in the background; after that the mic starts and stops it from here, and the text the app
/// hears comes back through the shared App Group store to be typed.
final class KeyboardViewController: UIInputViewController {
    private let keys = KeysView()
    private var heightConstraint: NSLayoutConstraint?
    private let tapFeel = UIImpactFeedbackGenerator(style: .light)

    private var changed: DarwinObserver?
    private var ackObserver: DarwinObserver?
    private var waitingForAck = false
    private var lastSpace = Date.distantPast
    private let suggester = Suggester()
    /// The last correction space made, so delete right after it can put the typed word back.
    private var lastFix: (typed: String, fixed: String)?
    /// listening, writing, or a note from the app: shown in the top bar instead of suggestions
    private var busyStatus: String?
    /// a quiet hint for when there's nothing to suggest
    private var hint: String?
    /// The latest suggestions and correction, worked out in the background for `word`.
    private var cached: (word: String, fix: String?)?
    private var ticket = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        keys.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keys)
        let height = view.heightAnchor.constraint(equalToConstant: KeysView.height(compact: false))
        height.priority = UILayoutPriority(999)
        heightConstraint = height
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keys.topAnchor.constraint(equalTo: view.topAnchor),
            keys.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        keys.onFeedback = { [weak self] in self?.feedback() }
        keys.onText = { [weak self] text in self?.type(text) }
        keys.onSpace = { [weak self] in self?.space() }
        keys.onDelete = { [weak self] word in self?.delete(word: word) }
        keys.onCursor = { [weak self] by in self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: by) }
        keys.onGlobe = { [weak self] in self?.advanceToNextInputMode() }
        keys.onMic = { [weak self] in self?.micTapped() }
        keys.onSuggestion = { [weak self] i in self?.pick(i) }
        requestSupplementaryLexicon { [weak self] lexicon in self?.suggester.use(lexicon) }
        suggester.warmUp()

        changed = DarwinObserver(KeyboardLink.changed) { [weak self] in KeyboardLink.log("kb", "changed received"); self?.refresh() }
        ackObserver = DarwinObserver(KeyboardLink.ack) { [weak self] in KeyboardLink.log("kb", "ack received"); self?.waitingForAck = false }
        KeyboardLink.log("kb", "loaded, fullAccess=\(hasFullAccess)")
        tapFeel.prepare()
        load()
    }

    /// iOS can keep an old copy of the keyboard alive (from before you switched apps) next to the
    /// one on screen. Only the copy on screen may type, or the old one would "type" into nothing.
    private var onScreen = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onScreen = true
        keys.showGlobe = needsInputModeSwitchKey
        refreshTextTraits()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onScreen = true
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onScreen = false
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // landscape gets shorter keys, like the regular keyboard
        let compact = view.bounds.width > 500
        if keys.compact != compact {
            keys.compact = compact
            heightConstraint?.constant = KeysView.height(compact: compact)
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshTextTraits()
    }

    // MARK: Typing

    private func type(_ text: String) {
        lastFix = nil
        textDocumentProxy.insertText(text)
        afterChange()
    }

    /// After every change: capitals, then fresh suggestions.
    private func afterChange() {
        autoCapitalize()
        updateSuggestions()
    }

    private var currentWord: String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return String(before.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
    }

    /// Suggestions and corrections are off where they'd get in the way: web addresses, email,
    /// and fields that ask for none.
    private var helpsHere: Bool {
        let p = textDocumentProxy
        if p.autocorrectionType == .no || p.spellCheckingType == .no { return false }
        return ![UIKeyboardType.URL, .emailAddress, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad].contains(p.keyboardType ?? .default)
    }

    /// Works out suggestions in the background; shows them when they're ready, if the word hasn't changed.
    private func updateSuggestions() {
        let word = helpsHere ? currentWord : ""
        ticket += 1
        let mine = ticket
        guard !word.isEmpty else {
            cached = nil
            keys.suggestions = []
            keys.bestSuggestion = nil
            applyTopBar()
            return
        }
        let suggester = self.suggester
        suggester.queue.async { [weak self] in
            let result = suggester.suggest(for: word)
            let fix = suggester.correction(for: word)
            DispatchQueue.main.async {
                guard let self, mine == self.ticket else { return }
                self.cached = (word, fix)
                self.keys.suggestions = result.words
                self.keys.bestSuggestion = result.best
                self.applyTopBar()
            }
        }
    }

    private func applyTopBar() {
        keys.status = busyStatus ?? (keys.suggestions.isEmpty ? hint : nil)
    }

    /// Tapping a suggestion swaps it in for the word being typed. The first slot keeps the word as typed.
    private func pick(_ i: Int) {
        let word = currentWord
        guard i < keys.suggestions.count else { return }
        var choice = keys.suggestions[i]
        if i == 0 {
            choice = word
            suggester.keep(word)
        }
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(choice + " ")
        lastFix = nil
        lastSpace = Date()
        afterChange()
    }

    /// Two spaces after a word make ". ", like the regular keyboard.
    private func space() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        // a small fix for the word just finished ("teh" → "the"), unless the field asks for none
        let word = currentWord
        // only a fix that's already worked out: space never waits on the spell checker
        if helpsHere, let c = cached, c.word == word, let fix = c.fix, fix != word {
            for _ in word { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(fix + " ")
            lastFix = (word, fix)
            lastSpace = Date()
            afterChange()
            return
        }
        lastFix = nil
        let quick = Date().timeIntervalSince(lastSpace) < 1.5
        if quick, before.hasSuffix(" "), let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpace = .distantPast
        } else {
            textDocumentProxy.insertText(" ")
            lastSpace = Date()
        }
        afterChange()
    }

    private func delete(word: Bool) {
        // delete right after a correction puts back what was typed, and leaves it alone from then on
        if !word, let fix = lastFix, (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(fix.fixed + " ") {
            for _ in 0..<(fix.fixed.count + 1) { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(fix.typed)
            suggester.keep(fix.typed)
            lastFix = nil
            afterChange()
            return
        }
        lastFix = nil
        if word {
            // the spaces before the cursor, then the word before them
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            var count = 0
            var seenWord = false
            for ch in before.reversed() {
                if ch.isWhitespace { if seenWord { break } } else { seenWord = true }
                count += 1
            }
            for _ in 0..<max(count, 1) { textDocumentProxy.deleteBackward() }
        } else {
            textDocumentProxy.deleteBackward()
        }
        afterChange()
    }

    /// Capital letter at the start of a sentence (or wherever the text field asks for one).
    private func autoCapitalize() {
        guard keys.shift != .locked else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let on: Bool
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: on = false
        case .allCharacters: on = true
        case .words: on = before.isEmpty || before.last?.isWhitespace == true
        default:
            let trimmed = before.reversed().drop { $0 == " " }
            on = before.isEmpty || before.hasSuffix("\n")
                || (before.hasSuffix(" ") && (trimmed.first.map { ".!?".contains($0) } ?? true))
        }
        keys.shift = on ? .on : .off
    }

    private func refreshTextTraits() {
        let titles: [UIReturnKeyType: String] = [.go: "go", .search: "search", .send: "send", .done: "done",
                                                 .next: "next", .join: "join", .route: "route", .continue: "continue",
                                                 .google: "search", .yahoo: "search"]
        keys.returnTitle = titles[textDocumentProxy.returnKeyType ?? .default]
        afterChange()
    }

    /// A light tap and the system click, like the regular keyboard. (Keyboards can only make
    /// haptics with Full Access on; the click follows the person's keyboard-clicks setting.)
    private func feedback() {
        if keys.micState == .listening {
            AudioServicesPlaySystemSound(1519)   // UIKit's haptics go quiet while the mic is recording
        } else {
            tapFeel.impactOccurred()
            tapFeel.prepare()
        }
        UIDevice.current.playInputClick()
    }

    // MARK: The app link

    /// Reads what the app has shared: the theme and the mic's state.
    private func load() {
        let d = KeyboardLink.read()
        if let saved = d[KeyboardLink.Key.theme] as? [String], saved.count == 6 { keys.colors = KeysView.Colors(saved) }
        let state = KeyboardLink.sessionAlive ? (KeyboardLink.State(rawValue: d[KeyboardLink.Key.state] as? String ?? "") ?? .off) : .off
        keys.micState = state
        busyStatus = nil
        if let note = d[KeyboardLink.Key.note] as? String {
            busyStatus = note.lowercased()
            keys.statusIsNote = true
        } else {
            keys.statusIsNote = false
            switch state {
            case .listening: busyStatus = "listening… tap the mic when you’re done"
            case .writing: busyStatus = "writing it down…"
            case .ready: hint = "mic on · tap to talk"
            case .off: hint = "tap the mic to talk"
            }
        }
        applyTopBar()
    }

    /// Reads what the app has shared, and types any new text it heard.
    private func refresh() {
        load()
        guard hasFullAccess, onScreen, view.window != nil else { return }
        let d = KeyboardLink.read()
        let mine = UserDefaults.standard   // the keyboard's own memory of what it already typed
        KeyboardLink.log("kb", "refresh: state=\(d[KeyboardLink.Key.state] as? String ?? "-") resultID=\((d[KeyboardLink.Key.resultID] as? String ?? "-").prefix(8)) inserted=\((mine.string(forKey: KeyboardLink.Key.inserted) ?? "-").prefix(8)) keys=\(d.count)")
        guard let id = d[KeyboardLink.Key.resultID] as? String,
              id != mine.string(forKey: KeyboardLink.Key.inserted),
              let text = d[KeyboardLink.Key.result] as? String else { return }
        mine.set(id, forKey: KeyboardLink.Key.inserted)
        // only type fresh results, so an old one never lands in the wrong place later
        let age = Date().timeIntervalSince1970 - (d[KeyboardLink.Key.resultAt] as? Double ?? 0)
        guard age < 120 else { KeyboardLink.log("kb", "result too old (\(Int(age))s), skipped"); return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let spacer = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") ? "" : " "
        textDocumentProxy.insertText(spacer + text)
        KeyboardLink.log("kb", "typed \(text.count) chars")
        afterChange()
    }

    /// Asks the app to start or stop. If it answers, stay here; if not (no session), open it.
    private func micTapped() {
        guard hasFullAccess else {
            busyStatus = "turn on allow full access: settings → general → keyboard → keyboards → utter"
            keys.statusIsNote = true
            applyTopBar()
            return
        }
        // a second tap while the first is still on its way would open the app twice
        guard !waitingForAck else { KeyboardLink.log("kb", "mic tapped again while waiting, ignored"); return }
        AudioServicesPlaySystemSound(1520)
        waitingForAck = true
        KeyboardLink.log("kb", "mic tapped, sent toggle")
        KeyboardLink.post(KeyboardLink.toggle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.waitingForAck else { return }
            self.waitingForAck = false
            KeyboardLink.log("kb", "no ack in time, opening app")
            self.openApp()
        }
    }

    /// Keyboards can't open apps through the normal API, so ask the app object up the responder chain.
    private func openApp() {
        let url = KeyboardLink.openURL as NSURL
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), NSStringFromClass(Swift.type(of: current)).contains("Application") {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: Open.self)
                open(current, selector, url, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        busyStatus = "open the utter app once, then come back"
        keys.statusIsNote = true
        applyTopBar()
    }
}
