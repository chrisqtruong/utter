import UIKit
import SwiftUI   // only for MarkerDot's path

// The Utter keyboard's keys, drawn and handled directly in UIKit so a key reacts the moment
// a finger lands. One view handles every touch (no buttons or gesture recognizers), which
// gives the regular keyboard's habits: the nearest key wins, sliding corrects a letter, a
// second finger commits the first (fast typing), and keys light up on touch-down.

enum KeyKind: Equatable {
    case char(String)
    case shift, delete, space, ret, mic, globe
    case mode(KeysView.Mode)
    case suggestion(Int)
}

final class KeysView: UIView, UIInputViewAudioFeedback {
    enum Mode { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    struct Colors {
        var bg, main, sub, alt, text, error: UIColor
        init(_ hex: [String]) {
            func c(_ i: Int) -> UIColor { UIColor(Color(hex: hex[i])) }
            bg = c(0); main = c(1); sub = c(2); alt = c(3); text = c(4); error = c(5)
        }
        /// shift, delete, 123, return: a step away from the letter keys, like the regular keyboard
        var function: UIColor { sub.withAlphaComponent(0.32) }
    }

    // MARK: State set by the keyboard

    var colors = Colors(["#323437", "#e2b714", "#646669", "#2c2e31", "#d1d0c5", "#ca4754"]) { didSet { restyle() } }
    var mode: Mode = .letters { didSet { if mode != oldValue { rebuild() } } }
    var shift: Shift = .off { didSet { if shift != oldValue { updateLabels() } } }
    var showGlobe = true { didSet { if showGlobe != oldValue { rebuild() } } }
    var micState: KeyboardLink.State = .off { didSet { if micState != oldValue { restyle() } } }
    /// "send", "go", "search"…; nil shows the return arrow
    var returnTitle: String? { didSet { if returnTitle != oldValue { restyle() } } }
    /// Shown in the top bar instead of suggestions (listening, writing, a note, or a hint).
    var status: String? { didSet { statusLabel.text = status; updateTopBar() } }
    /// Up to three words for the top bar; the one at `bestSuggestion` is what space will apply.
    var suggestions: [String] = [] { didSet { updateTopBar() } }
    var bestSuggestion: Int? { didSet { updateTopBar() } }
    var statusIsNote = false { didSet { statusLabel.textColor = statusIsNote ? colors.error : colors.sub } }
    /// landscape: shorter keys
    var compact = false { didSet { if compact != oldValue { setNeedsLayout() } } }

    // MARK: What the keys do

    var onText: (String) -> Void = { _ in }
    var onSpace: () -> Void = {}
    var onDelete: (_ word: Bool) -> Void = { _ in }
    var onMic: () -> Void = {}
    var onGlobe: () -> Void = {}
    var onCursor: (Int) -> Void = { _ in }
    var onFeedback: () -> Void = {}
    var onSuggestion: (Int) -> Void = { _ in }

    var enableInputClicksWhenVisible: Bool { true }

    struct Metrics { let strip, top, keyH, rowGap, side, gap, bottom: CGFloat }
    var metrics: Metrics { Self.metrics(compact: compact) }

    static func metrics(compact: Bool) -> Metrics {
        compact ? Metrics(strip: 36, top: 2, keyH: 34, rowGap: 7, side: 3, gap: 6, bottom: 3)
                : Metrics(strip: 46, top: 4, keyH: 43, rowGap: 11, side: 3, gap: 6, bottom: 4)
    }

    static func height(compact: Bool) -> CGFloat {
        let m = metrics(compact: compact)
        return m.strip + m.top + 4 * m.keyH + 3 * m.rowGap + m.bottom
    }

    // MARK: Views

    private var rows: [[KeyView]] = []
    /// The mic sits in the bar above the keys, away from space and return.
    private let micKey = KeyView(kind: .mic, units: 1)
    private let slots = (0..<3).map { KeyView(kind: .suggestion($0), units: 1) }
    private let dividers = (0..<2).map { _ in UIView() }
    private var allKeys: [KeyView] { rows.flatMap { $0 } + [micKey] + slots }
    private var showingSuggestions: Bool { status == nil && !suggestions.isEmpty }
    private let statusLabel = UILabel()
    private let popup = UIView()
    private let popupLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textAlignment = .left
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.8
        addSubview(statusLabel)
        popup.layer.cornerRadius = 9
        popup.isHidden = true
        popup.isUserInteractionEnabled = false
        popupLabel.font = .systemFont(ofSize: 30)
        popupLabel.textAlignment = .center
        popup.addSubview(popupLabel)
        addSubview(micKey)
        slots.forEach { addSubview($0) }
        dividers.forEach { addSubview($0) }
        rebuild()
        updateTopBar()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        rows = specs().map { row in row.map { KeyView(kind: $0.kind, units: $0.units) } }
        rows.flatMap { $0 }.forEach { insertSubview($0, belowSubview: popup) }
        bringSubviewToFront(popup)
        restyle()
        setNeedsLayout()
    }

    private struct Spec { let kind: KeyKind; let units: CGFloat }   // units < 0: fill the rest

    private func specs() -> [[Spec]] {
        func chars(_ s: String, _ w: CGFloat = 1) -> [Spec] { s.map { Spec(kind: .char(String($0)), units: w) } }
        var bottom = [Spec(kind: .mode(mode == .letters ? .numbers : .letters), units: 1.3)]
        if showGlobe { bottom.append(Spec(kind: .globe, units: 1.3)) }
        bottom += [Spec(kind: .space, units: -1), Spec(kind: .ret, units: 2.3)]
        let shiftKey = Spec(kind: .shift, units: 1.35), deleteKey = Spec(kind: .delete, units: 1.35)
        switch mode {
        case .letters:
            return [chars("qwertyuiop"), chars("asdfghjkl"), [shiftKey] + chars("zxcvbnm") + [deleteKey], bottom]
        case .numbers:
            return [chars("1234567890"), chars("-/:;()$&@\""),
                    [Spec(kind: .mode(.symbols), units: 1.35)] + chars(".,?!'", 1.45) + [deleteKey], bottom]
        case .symbols:
            return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"),
                    [Spec(kind: .mode(.numbers), units: 1.35)] + chars(".,?!'", 1.45) + [deleteKey], bottom]
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics, w = bounds.width
        // top bar: what's happening on the left, the mic on the right
        let micH = m.strip - 6
        micKey.frame = CGRect(x: w - m.side - 6 - micH * 1.25, y: 3, width: micH * 1.25, height: micH)
        statusLabel.frame = CGRect(x: 14, y: 0, width: micKey.frame.minX - 24, height: m.strip)
        let barX = m.side + 2, barW = micKey.frame.minX - 10 - barX, slotW = barW / 3
        for (i, slot) in slots.enumerated() {
            slot.frame = CGRect(x: barX + CGFloat(i) * slotW + 2, y: 5, width: slotW - 4, height: m.strip - 10)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: barX + CGFloat(i + 1) * slotW - 0.5, y: 14, width: 1, height: m.strip - 28)
        }
        let unit = (w - 2 * m.side - 9 * m.gap) / 10
        for (r, row) in rows.enumerated() {
            let y = m.strip + m.top + CGFloat(r) * (m.keyH + m.rowGap)
            var widths = row.map { $0.units * unit }
            var xs: [CGFloat] = []
            if r == 3 {
                // bottom row: space takes whatever is left
                let fixed = widths.filter { $0 >= 0 }.reduce(0, +) + m.gap * CGFloat(row.count - 1)
                widths = widths.map { $0 < 0 ? w - 2 * m.side - fixed : $0 }
                var x = m.side
                for wd in widths { xs.append(x); x += wd + m.gap }
            } else if r == 2 {
                // shift (or #+=) at the left edge, delete at the right, the rest centered between
                let mid = widths.dropFirst().dropLast()
                let midTotal = mid.reduce(0, +) + m.gap * CGFloat(mid.count - 1)
                var x = (w - midTotal) / 2
                xs.append(m.side)
                for wd in mid { xs.append(x); x += wd + m.gap }
                xs.append(w - m.side - widths.last!)
            } else {
                let total = widths.reduce(0, +) + m.gap * CGFloat(row.count - 1)
                var x = (w - total) / 2
                for wd in widths { xs.append(x); x += wd + m.gap }
            }
            for (i, key) in row.enumerated() {
                key.frame = CGRect(x: xs[i], y: y, width: widths[i], height: m.keyH)
            }
        }
    }

    /// The key a finger at this point means: its row by height, then the nearest key in that row.
    /// So the gaps between keys, and the strip above, still land on a key.
    private func key(at p: CGPoint) -> KeyView? {
        let m = metrics, top = m.strip + m.top
        if p.y < top - m.rowGap / 2 {
            if p.x > micKey.frame.minX - 16 { return micKey }   // generous around the mic
            if showingSuggestions, p.y < m.strip - 2 {
                return slots.min { abs($0.frame.midX - p.x) < abs($1.frame.midX - p.x) }.flatMap { $0.isHidden ? nil : $0 }
            }
        }
        let r = min(max(Int(floor((p.y - top + m.rowGap / 2) / (m.keyH + m.rowGap))), 0), rows.count - 1)
        func dist(_ k: KeyView) -> CGFloat { p.x < k.frame.minX ? k.frame.minX - p.x : p.x > k.frame.maxX ? p.x - k.frame.maxX : 0 }
        return rows[r].min { dist($0) < dist($1) }
    }

    // MARK: Look

    private func restyle() {
        backgroundColor = colors.bg
        statusLabel.textColor = statusIsNote ? colors.error : colors.sub
        popup.backgroundColor = colors.alt
        popupLabel.textColor = colors.text
        popup.layer.shadowColor = UIColor.black.cgColor
        popup.layer.shadowOpacity = 0.25
        popup.layer.shadowRadius = 3
        popup.layer.shadowOffset = CGSize(width: 0, height: 1)
        for key in allKeys { key.style(colors, mic: micState, returnTitle: returnTitle) }
        dividers.forEach { $0.backgroundColor = colors.sub.withAlphaComponent(0.3) }
        updateLabels()
    }

    private func updateTopBar() {
        let show = showingSuggestions
        statusLabel.isHidden = show
        for (i, slot) in slots.enumerated() {
            slot.isHidden = !show || i >= suggestions.count
            slot.setSuggestion(i < suggestions.count ? suggestions[i] : "", best: i == bestSuggestion)
        }
        for (i, d) in dividers.enumerated() { d.isHidden = !show || i + 1 >= suggestions.count }
    }

    private func updateLabels() {
        for key in rows.flatMap({ $0 }) { key.update(shift: shift) }
    }

    // MARK: Touches

    private final class Press {
        var key: KeyView
        let fromMode: Bool
        var cursorMode = false
        var lastX: CGFloat
        var committed = false
        init(key: KeyView, fromMode: Bool, x: CGFloat) { self.key = key; self.fromMode = fromMode; lastX = x }
    }

    private var presses: [ObjectIdentifier: Press] = [:]
    private var deleteTimer: Timer?
    private var spaceTimer: Timer?
    private var lastShiftTap = Date.distantPast

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // fast typing: a new finger finishes the key the last one is still on
            for press in presses.values where !press.committed { if case .char = press.key.kind { commit(press) } }
            guard let key = key(at: touch.location(in: self)) else { continue }
            let press = Press(key: key, fromMode: { if case .mode = key.kind { return true }; return false }(), x: touch.location(in: self).x)
            presses[ObjectIdentifier(touch)] = press
            key.pressed = true
            onFeedback()
            switch key.kind {
            case .char: showPopup(for: key)
            case .delete:
                onDelete(false)
                startDeleteRepeat()
            case .shift:
                let now = Date()
                if now.timeIntervalSince(lastShiftTap) < 0.3 { shift = .locked }
                else { shift = shift == .off ? .on : .off }
                lastShiftTap = now
            case .mode(let m):
                mode = m   // switch right away, so a finger can slide onto the new keys
            case .space:
                spaceTimer?.invalidate()
                spaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak press] _ in
                    guard let self, let press, !press.committed else { return }
                    press.cursorMode = true
                    self.onFeedback()
                    self.allKeys.forEach { $0.dimmed = true }
                }
            default: break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses[ObjectIdentifier(touch)], !press.committed else { continue }
            let p = touch.location(in: self)
            if case .space = press.key.kind, press.cursorMode {
                // hold the space bar and slide: move the text cursor, a letter per ~9 points
                let steps = Int((p.x - press.lastX) / 9)
                if steps != 0 { onCursor(steps); press.lastX += CGFloat(steps) * 9 }
                continue
            }
            let isChar: Bool = { if case .char = press.key.kind { return true }; return false }()
            guard isChar || press.fromMode, let next = key(at: p), next !== press.key else { continue }
            guard case .char = next.kind else { continue }
            press.key.pressed = false
            press.key = next
            next.pressed = true
            showPopup(for: next)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            if !press.committed { commit(press) }
            finish(press)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            press.committed = true
            finish(press)
        }
    }

    private func commit(_ press: Press) {
        press.committed = true
        switch press.key.kind {
        case .char(let s):
            onText(shift == .off ? s : s.uppercased())
            if shift == .on { shift = .off }
            if mode != .letters, s == "'" || press.fromMode { mode = .letters }
        case .space:
            if !press.cursorMode {
                onSpace()
                if mode != .letters { mode = .letters }
            }
        case .ret: onText("\n")
        case .mic: onMic()
        case .globe: onGlobe()
        case .suggestion(let i): onSuggestion(i)
        default: break
        }
        hidePopup(for: press.key)
        press.key.pressed = false
    }

    private func finish(_ press: Press) {
        press.key.pressed = false
        hidePopup(for: press.key)
        switch press.key.kind {
        case .delete: deleteTimer?.invalidate(); deleteTimer = nil
        case .space:
            spaceTimer?.invalidate(); spaceTimer = nil
            if press.cursorMode { allKeys.forEach { $0.dimmed = false } }
        default: break
        }
    }

    /// Hold delete: after a moment it repeats, and after a couple of seconds it takes whole words.
    private func startDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            var ticks = 0
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                guard let self else { return }
                ticks += 1
                if ticks < 22 { self.onDelete(false) }            // letters for about two seconds
                else if ticks % 3 == 0 { self.onDelete(true) }    // then a word at a time, a bit slower
            }
        }
    }

    // MARK: Popup

    private func showPopup(for key: KeyView) {
        guard case .char = key.kind else { return }
        popupLabel.text = key.displayText
        let w = key.frame.width + 16, h: CGFloat = compact ? 38 : 48
        var x = key.frame.midX - w / 2
        x = min(max(x, 1), bounds.width - w - 1)
        let y = max(0, key.frame.minY - h + 8)
        popup.frame = CGRect(x: x, y: y, width: w, height: h)
        popupLabel.frame = popup.bounds.insetBy(dx: 0, dy: 2)
        popup.layer.shadowPath = UIBezierPath(roundedRect: popup.bounds, cornerRadius: 9).cgPath
        popup.isHidden = false
        popup.tag = key.hash
    }

    private func hidePopup(for key: KeyView) {
        if popup.tag == key.hash { popup.isHidden = true }
    }
}

// MARK: - One key

final class KeyView: UIView {
    let kind: KeyKind
    let units: CGFloat
    private let label = UILabel()
    private let icon = UIImageView()
    private let dot = CAShapeLayer()
    private var colors: KeysView.Colors?
    private var micState: KeyboardLink.State = .off
    private var returnTitle: String?
    private(set) var displayText = ""

    var pressed = false { didSet { if pressed != oldValue { paint() } } }
    var dimmed = false { didSet { alpha = dimmed ? 0.35 : 1 } }
    private var best = false

    /// For the suggestion slots in the top bar.
    func setSuggestion(_ text: String, best: Bool) {
        label.text = text
        self.best = best
        label.font = .systemFont(ofSize: 16, weight: best ? .semibold : .regular)
        paint()
    }

    init(kind: KeyKind, units: CGFloat) {
        self.kind = kind
        self.units = units
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 7
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        if case .mic = kind {
            // just the marker dot, no key behind it, with the app's soft drop shadow
            layer.shadowOpacity = 0
            dot.shadowColor = UIColor.black.cgColor
            dot.shadowOpacity = 0.16
            dot.shadowRadius = 0
            dot.shadowOffset = CGSize(width: 0, height: 2.5)
            layer.addSublayer(dot)
        }
        label.textAlignment = .center
        icon.contentMode = .center
        addSubview(label)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isFunction: Bool {
        switch kind {
        case .char, .space: return false
        default: return true
        }
    }

    func style(_ c: KeysView.Colors, mic: KeyboardLink.State, returnTitle: String?) {
        colors = c
        micState = mic
        self.returnTitle = returnTitle
        label.textColor = c.text
        icon.tintColor = c.text
        switch kind {
        case .char:
            label.font = .systemFont(ofSize: 23)
        case .space:
            label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            label.text = "space"
        case .mode(let m):
            label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            label.text = m == .letters ? "ABC" : m == .numbers ? "123" : "#+="
        case .ret:
            if let returnTitle {
                label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
                label.text = returnTitle
                label.textColor = c.bg
                icon.image = nil
            } else {
                label.text = nil
                icon.image = UIImage(systemName: "return", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
            }
        case .delete:
            icon.image = UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
        case .globe:
            icon.image = UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
        case .mic:
            dot.fillColor = (mic == .listening ? c.error : c.main).cgColor
            let symbol = mic == .listening ? "stop.fill" : "mic.fill"
            icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
            icon.tintColor = c.bg
            alpha = mic == .writing ? 0.45 : 1
        case .shift:
            break
        case .suggestion:
            layer.shadowOpacity = 0
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.lineBreakMode = .byTruncatingMiddle
        }
        paint()
    }

    func update(shift: KeysView.Shift) {
        switch kind {
        case .char(let s):
            displayText = shift == .off ? s : s.uppercased()
            label.text = displayText
        case .shift:
            let name = shift == .locked ? "capslock.fill" : shift == .on ? "shift.fill" : "shift"
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
        default: break
        }
    }

    private func paint() {
        guard let c = colors else { return }
        if case .suggestion = kind {
            backgroundColor = pressed ? c.function : best ? c.alt : .clear
            return
        }
        if case .mic = kind {
            backgroundColor = .clear
            transform = pressed ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            return
        }
        if case .ret = kind, returnTitle != nil {
            backgroundColor = pressed ? c.main.withAlphaComponent(0.7) : c.main
        } else if isFunction {
            backgroundColor = pressed ? c.alt : c.function
        } else {
            backgroundColor = pressed ? c.function : c.alt
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        icon.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 7).cgPath
        if case .mic = kind {
            let side = min(bounds.width, bounds.height) - 2
            let r = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            dot.path = MarkerDot().path(in: r).cgPath
        }
    }
}
