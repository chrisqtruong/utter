import UIKit

/// Sends you back to the app you were typing in after the Utter keyboard opened Utter.
///
/// iOS has no public way to do this, so it's a best effort with a fallback (the arrow on home):
/// 1. Find out which app you came from. The keyboard asks iOS (works before iOS 26.4) and passes
///    it along in the link; otherwise Utter reads it from UIKit's keyboard state, which carries the
///    app that showed the keyboard. Neither is a documented API: if either disappears, this quietly
///    does nothing.
/// 2. Open that app again through its own link (Notes, Messages, Slack…). Apps not in the list
///    can't be reopened this way.
/// The approach follows OpenWhispr's (github.com/OpenWhispr/openwhispr, PR #2365).
@MainActor
enum HostReturn {
    struct Host { let name: String; let url: URL }

    /// Apps Utter knows how to reopen: bundle ID → name and link.
    static let catalog: [String: (name: String, url: String)] = [
        "com.apple.mobilenotes": ("notes", "mobilenotes://"),
        "com.apple.MobileSMS": ("messages", "sms://"),
        "com.apple.mobilemail": ("mail", "message://"),
        "com.apple.reminders": ("reminders", "x-apple-reminderkit://"),
        "com.tinyspeck.chatlyio": ("slack", "slack://"),
        "net.whatsapp.WhatsApp": ("whatsapp", "whatsapp://"),
        "com.google.Gmail": ("gmail", "googlegmail://"),
        "com.microsoft.Office.Outlook": ("outlook", "ms-outlook://"),
        "md.obsidian": ("obsidian", "obsidian://"),
        "notion.id": ("notion", "notion://"),
        "com.hammerandchisel.discord": ("discord", "discord://"),
        "ph.telegra.Telegraph": ("telegram", "tg://"),
        "com.burbn.instagram": ("instagram", "instagram://"),
        "com.facebook.Messenger": ("messenger", "fb-messenger://"),
        "com.atebits.Tweetie2": ("x", "twitter://"),
        "com.linkedin.LinkedIn": ("linkedin", "linkedin://"),
        "com.google.chrome.ios": ("chrome", "googlechrome://"),
    ]

    static func host(for bundleID: String?) -> Host? {
        guard let bundleID, let entry = catalog[bundleID], let url = URL(string: entry.url) else { return nil }
        return Host(name: entry.name, url: url)
    }

    /// Which app showed the keyboard, from the link first, then from UIKit (waits up to 2 s for it).
    static func findHost(fromLink link: URL) async -> String? {
        if let id = URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "host" })?.value, !id.isEmpty {
            return id
        }
        let own = Bundle.main.bundleIdentifier ?? ""
        for _ in 0..<20 {
            if let id = keyboardSourceApp(), !id.hasPrefix(own) { return id }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Opens the app again. Returns false if it couldn't.
    static func go(to host: Host) async -> Bool {
        await withCheckedContinuation { done in
            UIApplication.shared.open(host.url, options: [:]) { ok in done.resume(returning: ok) }
        }
    }

    /// UIKit's record of the app whose text field is showing a keyboard. Private, so every step
    /// checks first and gives up quietly.
    private static func keyboardSourceApp() -> String? {
        guard let cls = NSClassFromString("_UIRemoteKeyboards") as? NSObject.Type,
              cls.responds(to: NSSelectorFromString("sharedRemoteKeyboards")),
              let shared = cls.perform(NSSelectorFromString("sharedRemoteKeyboards"))?.takeUnretainedValue() as? NSObject,
              shared.responds(to: NSSelectorFromString("currentState")),
              let state = shared.perform(NSSelectorFromString("currentState"))?.takeUnretainedValue() as? NSObject,
              state.responds(to: NSSelectorFromString("sourceBundleIdentifier"))
        else { return nil }
        return state.perform(NSSelectorFromString("sourceBundleIdentifier"))?.takeUnretainedValue() as? String
    }
}
