import Foundation

/// How the Utter keyboard and the app talk. iOS doesn't let keyboards use the microphone,
/// so the app does the listening (in a background "session") and the keyboard just shows
/// the button and types the text. They share a small settings store in the App Group, and
/// nudge each other with system-wide ("Darwin") notifications.
enum KeyboardLink {
    static let group = "group.com.christruong.utter"
    static let openURL = URL(string: "utter://keyboard")!

    enum Key {
        static let state = "kb.state"          // State.rawValue
        static let alive = "kb.alive"          // seconds since 1970, refreshed every second while a session runs
        static let result = "kb.result"        // the latest text for the keyboard to type
        static let resultID = "kb.resultID"    // changes with each new result
        static let resultAt = "kb.resultAt"    // when it was made
        static let inserted = "kb.inserted"    // the last resultID the keyboard typed
        static let note = "kb.note"            // a short message for the keyboard ("didn't hear any talking")
        static let theme = "kb.theme"          // [bg, main, sub, subAlt, text, error] hex, mirrored from the app
    }

    enum State: String { case off, ready, listening, writing }

    /// keyboard → app: start or stop listening
    static let toggle = "com.christruong.utter.kb.toggle"
    /// app → keyboard: something changed, read the store again
    static let changed = "com.christruong.utter.kb.changed"

    /// app → keyboard: "got your tap", so the keyboard doesn't open the app
    static let ack = "com.christruong.utter.kb.ack"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    // MARK: Shared status file
    // A small file in the App Group, read fresh every time. (Shared UserDefaults can hand the
    // keyboard an out-of-date value, which made it think no session was running.)

    /// In the group's Library folder (where Xcode's device tools can read it, for debugging).
    private static var folder: URL? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Library", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL? { folder?.appendingPathComponent("keyboard.plist") }

    /// A short trail of what happened, from both the app and the keyboard, for debugging the hand-off.
    /// Keeps only the last ~200 lines.
    static func log(_ who: String, _ what: String) {
        guard let url = folder?.appendingPathComponent("keyboard-log.txt") else { return }
        let stamp = String(format: "%.2f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10_000))
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append("\(stamp) \(who): \(what)")
        try? lines.suffix(200).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func read() -> [String: Any] {
        guard let url = fileURL, let d = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        return d
    }

    /// Merges these values into the file (nil removes a key). Only the app writes it.
    static func write(_ changes: [String: Any?]) {
        guard let url = fileURL else { return }
        var d = read()
        for (k, v) in changes { d[k] = v }
        if !(d as NSDictionary).write(to: url, atomically: true) { log("app", "WRITE FAILED keys=\(changes.keys.sorted())") }
    }

    /// True while the app is running a keyboard session (it refreshes `alive` every second).
    static var sessionAlive: Bool {
        guard let t = read()[Key.alive] as? Double, t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < 3
    }

    static var state: State {
        State(rawValue: read()[Key.state] as? String ?? "") ?? .off
    }
}

/// Calls `handler` on the main thread whenever the named Darwin notification is posted.
final class DarwinObserver {
    private let handler: () -> Void

    init(_ name: String, handler: @escaping () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.handler() }
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
