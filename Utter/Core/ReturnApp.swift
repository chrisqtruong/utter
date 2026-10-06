import UIKit

/// After the Utter keyboard opens the app, Utter can jump straight back to the app you dictate
/// into most. iOS doesn't tell an app where it was opened from, so this is a fixed choice, made
/// with each app's public link (the same kind a web page uses to open an app).
struct ReturnApp: Identifiable, Hashable {
    let id: String
    let name: String
    let link: String

    var url: URL? { URL(string: link) }

    static let storageKey = "returnApp"

    /// Apple's apps first, then common ones. Only the ones on this iPhone are offered.
    /// Each scheme also has to be listed under LSApplicationQueriesSchemes in project.yml.
    static let all: [ReturnApp] = [
        ReturnApp(id: "notes", name: "Notes", link: "mobilenotes://"),
        ReturnApp(id: "messages", name: "Messages", link: "sms:"),
        ReturnApp(id: "mail", name: "Mail", link: "message://"),
        ReturnApp(id: "reminders", name: "Reminders", link: "x-apple-reminderkit://"),
        ReturnApp(id: "whatsapp", name: "WhatsApp", link: "whatsapp://"),
        ReturnApp(id: "signal", name: "Signal", link: "sgnl://"),
        ReturnApp(id: "telegram", name: "Telegram", link: "tg://"),
        ReturnApp(id: "slack", name: "Slack", link: "slack://"),
        ReturnApp(id: "discord", name: "Discord", link: "discord://"),
        ReturnApp(id: "gmail", name: "Gmail", link: "googlegmail://"),
        ReturnApp(id: "outlook", name: "Outlook", link: "ms-outlook://"),
        ReturnApp(id: "teams", name: "Teams", link: "msteams://"),
        ReturnApp(id: "obsidian", name: "Obsidian", link: "obsidian://"),
        ReturnApp(id: "notion", name: "Notion", link: "notion://"),
        ReturnApp(id: "bear", name: "Bear", link: "bear://"),
        ReturnApp(id: "drafts", name: "Drafts", link: "drafts://"),
        ReturnApp(id: "dayone", name: "Day One", link: "dayone://"),
        ReturnApp(id: "googledocs", name: "Google Docs", link: "googledocs://"),
        ReturnApp(id: "instagram", name: "Instagram", link: "instagram://"),
    ]

    @MainActor
    static var installed: [ReturnApp] {
        all.filter { app in app.url.map { UIApplication.shared.canOpenURL($0) } ?? false }
    }

    /// The chosen app, or nil to stay in Utter.
    static var chosen: ReturnApp? {
        let id = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return all.first { $0.id == id }
    }
}
