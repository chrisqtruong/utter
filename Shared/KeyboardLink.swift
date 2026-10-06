import Foundation

/// How the Utter keyboard and the app talk. iOS doesn't let keyboards use the microphone,
/// so the app does the listening (in a background "session") and the keyboard just shows
/// the button and types the text. They share a small settings store in the App Group, and
/// nudge each other with system-wide ("Darwin") notifications.
enum KeyboardLink {
    static let group = "group.com.christruong.utter"
    static var store: UserDefaults? { UserDefaults(suiteName: group) }
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

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// True while the app is running a keyboard session (it refreshes `alive` every second).
    static var sessionAlive: Bool {
        guard let t = store?.double(forKey: Key.alive), t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < 3
    }

    static var state: State {
        State(rawValue: store?.string(forKey: Key.state) ?? "") ?? .off
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
