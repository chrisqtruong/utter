import AppIntents

/// "Dictate" — opens Utter and starts listening; run it again to stop.
/// Put it on the Action button: Settings → Action Button → Shortcut → Utter → Dictate.
struct DictateIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate"
    static let description = IntentDescription("Opens Utter and starts listening. Run it again to stop; the text is copied for you.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.dictator.toggleFromShortcut()
        return .result()
    }
}

struct UtterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: ["Dictate with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Dictate",
            systemImageName: "waveform"
        )
    }
}
