import SwiftUI

/// Everything the app shares, in one place the Shortcut can reach too.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let history = History()
    let models = ModelStore()
    let vocabulary = Vocabulary()
    let voice = VoiceProfile()
    let dictator: Dictator
    let keyboard: KeyboardSession

    private init() {
        dictator = Dictator(models: models, history: history, vocabulary: vocabulary, voice: voice)
        keyboard = KeyboardSession(dictator: dictator)
        history.applyKeepLimit()
        #if DEBUG
        if CommandLine.arguments.contains("-seedDemo") { history.seedDemo() }
        #endif
    }
}

@main
struct UtterApp: App {
    private let app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(app.history)
                .environment(app.models)
                .environment(app.dictator)
                .environment(app.vocabulary)
                .environment(app.voice)
                .environment(app.keyboard)
                // a file shared to Utter from another app ("Open in Utter")
                .onOpenURL { url in
                    if url.scheme == "utter" { app.keyboard.startFromKeyboard() }   // the Utter keyboard asked to listen
                    else { Task { await app.dictator.transcribeFile(url) } }
                }
                .task {
                    await app.models.loadSelected()
                    #if DEBUG
                    await app.dictator.runTestFileIfAsked()
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // open writing models use the graphics chip, which iOS doesn't allow in the background:
            // stop as soon as Utter starts to leave the screen, then free the memory
            if phase != .active { Task { await WriterEngine.shared.stopAndUnload() } }
            switch phase {
            case .active:
                app.models.refresh()
                app.dictator.appBecameActive()
                app.keyboard.cameBack()
                Task { await app.dictator.processCaptures() }
            case .background:
                app.dictator.appWentToBackground()
                app.keyboard.leftApp()

            default: break
            }
        }
    }
}

/// Applies the chosen theme. "auto" follows the system's light or dark mode.
private struct ThemedRoot: View {
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("theme") private var themeName = Themes.autoName

    var body: some View {
        let theme = Themes.named(themeName, systemDark: systemScheme == .dark)
        HomeView()
            .environment(\.theme, theme)
            // the keyboard draws itself in the same colors
            .onAppear { KeyboardLink.write([KeyboardLink.Key.theme: theme.hex]) }
            .onChange(of: theme.name) { _, _ in KeyboardLink.write([KeyboardLink.Key.theme: theme.hex]) }
            .tint(theme.main)
            .preferredColorScheme(themeName == Themes.autoName ? nil : (theme.isDark ? .dark : .light))
            // follows the iPhone's text size, up to a size the layouts can still hold
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
