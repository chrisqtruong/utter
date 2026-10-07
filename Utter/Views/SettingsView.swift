import SwiftUI

struct SettingsView: View {
    @Environment(ModelStore.self) private var models
    @Environment(History.self) private var history
    @Environment(Vocabulary.self) private var vocabulary
    @Environment(VoiceProfile.self) private var voice
    @Environment(\.theme) private var theme
    @AppStorage("theme") private var themeName = Themes.autoName
    @AppStorage("language") private var language = "auto"
    @AppStorage("autoCopy") private var autoCopy = true
    @AppStorage("removeFillers") private var removeFillers = true
    @AppStorage("showShaky") private var showShaky = true
    @AppStorage("aiTitles") private var aiTitles = true
    @AppStorage("autoTidy") private var autoTidy = false
    @AppStorage(ReturnApp.storageKey) private var returnID = ""   // so the keyboard row updates

    var body: some View {
        NavigationStack {
            Page(title: "settings") {
                statsTeaser

                PageSection(label: "speech") {
                    NavigationLink { ModelsView() } label: {
                        // speech · writing, e.g. "parakeet v3 · qwen3.5 2b"
                        PageRow(title: "Models", value: "\(models.selected?.name.lowercased() ?? "none") · \(WriterStore.shared.selected.isBuiltIn ? "apple" : WriterStore.shared.selected.name.lowercased())")
                    }
                    NavigationLink { VoiceCheckView() } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Voice check").font(.ui(17)).foregroundStyle(theme.text)
                            Spacer(minLength: 12)
                            // when you last ran it; nudges once it's never been done or it's been a while
                            Text(voice.lastRunLabel.map { "done \($0)" } ?? "not yet · 1 min")
                                .font(.mono(14))
                                .foregroundStyle(voice.isStale ? theme.main : theme.sub)
                            Text("→").font(.mono(15)).foregroundStyle(theme.sub)
                        }
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    NavigationLink { DictionaryView() } label: {
                        PageRow(title: "Dictionary", value: vocabulary.entries.isEmpty ? "add words" : vocabulary.entries.count == 1 ? "1 word" : "\(vocabulary.entries.count) words")
                    }
                    Menu {
                        Picker("Language", selection: $language) {
                            ForEach(Languages.options, id: \.code) { Text($0.name).tag($0.code) }
                        }
                    } label: {
                        PageRow(title: "Language", value: language == "auto" ? "auto" : Languages.options.first { $0.code == language }?.name.lowercased())
                    }
                }

                PageSection(label: "after you stop",
                            note: Assistant.isAvailable ? nil : "Naming notes and tidy need a writing model (Models). \(Assistant.unavailableReason)") {
                    MarkerToggle(title: "Copy the text", isOn: $autoCopy)
                    MarkerToggle(title: "Remove ums and uhs", isOn: $removeFillers)
                    MarkerToggle(title: "Underline shaky words", isOn: $showShaky)
                    MarkerToggle(title: "Name longer notes", isOn: $aiTitles)
                        .disabled(!Assistant.isAvailable)
                        .opacity(Assistant.isAvailable ? 1 : 0.45)
                    MarkerToggle(title: "Tidy automatically", isOn: $autoTidy)
                        .disabled(!Assistant.isAvailable)
                        .opacity(Assistant.isAvailable ? 1 : 0.45)

                }

                PageSection(label: "look") {
                    NavigationLink { ThemesView() } label: { PageRow(title: "Theme", value: themeName) }
                    NavigationLink { AppIconView() } label: { PageRow(title: "App icon", value: currentIcon.label) }
                }

                PageSection(label: "more") {
                    NavigationLink { StorageView() } label: {
                        PageRow(title: "Storage")
                    }
                    NavigationLink { KeyboardSettingsView() } label: {
                        PageRow(title: "Keyboard", value: ReturnApp.chosen.map { "back to \($0.name.lowercased())" })
                    }
                    NavigationLink { ActionButtonView() } label: { PageRow(title: "Action button") }
                    NavigationLink { ScoreInfoView() } label: { PageRow(title: "How the match score works") }
                    NavigationLink { AboutView() } label: { PageRow(title: "About & privacy") }
                }

                Text("utter \(Self.version)")
                    .font(.mono(12))
                    .foregroundStyle(theme.sub.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// "0.1 (1)": the version and build number from the app itself.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var currentIcon: AppIconOption {
        let id = UIApplication.shared.alternateIconName ?? "AppIcon"
        return AppIcons.options.first { $0.id == id } ?? AppIcons.options[0]
    }

    private var statsTeaser: some View {
        let stats = Stats(history.items)
        return NavigationLink { StatsView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "your stats")
                    Spacer()
                    Text("→").font(.mono(15)).foregroundStyle(theme.sub)
                }
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    bigNumber(stats.words.formatted(), "words")
                    bigNumber(formatMinutes(stats.minutesSaved), "saved")
                    bigNumber("\(stats.streakDays)", "day streak")
                }
                WeekStrokes(week: stats.week).frame(height: 48)
            }
            .padding(14)
            .background(theme.subAlt.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bigNumber(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.mono(22, .semibold)).foregroundStyle(theme.text)
            Text(label).font(.mono(11)).foregroundStyle(theme.sub)
        }
    }
}

// MARK: - App icon

struct AppIconView: View {
    @Environment(\.theme) private var theme
    @State private var iconID = UIApplication.shared.alternateIconName ?? "AppIcon"

    /// iOS turns down an icon change while its "you have changed the icon" notice is still up,
    /// so keep trying for a little while (until the notice is dismissed).
    @MainActor
    static func setIcon(_ name: String?) async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if UIApplication.shared.alternateIconName == name { return }
            let worked: Bool = await withCheckedContinuation { done in
                UIApplication.shared.setAlternateIconName(name) { error in done.resume(returning: error == nil) }
            }
            if worked { return }
        }
    }

    var body: some View {
        Page(title: "app icon", showsDone: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 24)], spacing: 28) {
                ForEach(AppIcons.options) { option in
                    let on = iconID == option.id
                    Button {
                        iconID = option.id
                        let name = option.isDefault ? nil : option.id
                        if UIApplication.shared.alternateIconName == name, name != nil {
                            // Tapping the current one again redraws it (after an update the home screen
                            // can show a blank icon until it's set fresh).
                            UIApplication.shared.setAlternateIconName(nil) { _ in
                                Task { @MainActor in await Self.setIcon(name) }
                            }
                        } else {
                            UIApplication.shared.setAlternateIconName(name)
                        }
                    } label: {
                        VStack(spacing: 10) {
                            IconArt(option: option)
                                .frame(width: 72, height: 72)
                                .markerLoop(on, seed: option.id, color: theme.main, round: true, pad: 8)
                            Text(option.label).font(.mono(12)).foregroundStyle(on ? theme.text : theme.sub)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.label) icon")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 12)
            .onAppear { iconID = UIApplication.shared.alternateIconName ?? "AppIcon" }
            Text("iOS shows a short notice when the icon changes. That's normal. If the home screen icon ever looks blank, tap your icon here again.")
                .font(.ui(14)).foregroundStyle(theme.sub)
        }
    }
}

// MARK: - Action button

struct ActionButtonView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Page(title: "action button", showsDone: false) {
            Text("Start Utter with one press, from anywhere, even the lock screen.")
                .font(.ui(17)).foregroundStyle(theme.text)
            PageSection(label: "set it up") {
                step("1", "Open iPhone Settings → Action Button")
                step("2", "Swipe to Shortcut, then tap Choose a Shortcut")
                step("3", "Pick Utter → Dictate")
            }
            PageSection(label: "use it") {
                step("·", "Press once: Utter opens and starts listening")
                step("·", "Press again, or tap stop: the text is ready and copied")
                step("·", "Lock the screen mid-thought: it keeps listening")
            }
            PageSection(label: "no action button?") {
                Text("In the Shortcuts app, make a shortcut with Utter's Dictate action, then pick it under Settings → Accessibility → Touch → Back Tap. A double tap on the back of the phone starts Utter.")
                    .font(.ui(15)).foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(n).font(.mono(14, .semibold)).foregroundStyle(theme.main).frame(width: 12)
            Text(text).font(.ui(16)).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Page(title: "about", showsDone: false) {
            PageSection(label: "privacy") {
                para("Everything happens on this iPhone. Your voice is turned into text here and the recording is thrown away as soon as it's done. Only the text goes into history.")
                para("Turning phone audio into text (what's playing) is the one exception: the sound is saved on this iPhone while it's captured, because the screen recording add-on can't run a speech model itself. Utter deletes it as soon as it's turned into text. Files you share to Utter are deleted after too.")
                para("No account, no tracking. The internet is only used to download speech models when you ask.")
            }
            PageSection(label: "made with") {
                para("Speech by WhisperKit (Argmax) and FluidAudio, running NVIDIA's Parakeet and OpenAI's Whisper. Writing help by Apple Intelligence, on device.")
                para("Inspired by SpeakType. Themes from Monkeytype, by way of Vox2. Hand-drawn marks from chrisqtruong.github.io.")
            }
        }
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.ui(16)).foregroundStyle(theme.text.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Themes

struct ThemesView: View {
    @Environment(\.theme) private var theme
    @AppStorage("theme") private var themeName = Themes.autoName

    var body: some View {
        Page(title: "theme", showsDone: false) {
            PageSection(label: "auto") {
                swatch(name: Themes.autoName, preview: [Themes.named("serika", systemDark: false), Themes.named("serika dark", systemDark: true)])
                Text("Follows your iPhone: light by day, dark at night.")
                    .font(.ui(14)).foregroundStyle(theme.sub)
            }
            ForEach(Themes.groups) { group in
                PageSection(label: group.name) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 18)], spacing: 18) {
                        ForEach(group.themes) { t in swatch(name: t.name, preview: [t]) }
                    }
                }
            }
        }
    }

    private func swatch(name: String, preview: [Theme]) -> some View {
        let selected = themeName == name
        return Button { themeName = name } label: {
            HStack(spacing: 0) {
                ForEach(preview) { t in
                    HStack(spacing: 8) {
                        Text(preview.count > 1 ? (t.isDark ? "dark" : "light") : name)
                            .font(.mono(13))
                            .foregroundStyle(t.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        HStack(spacing: 3) {
                            MarkerDot().fill(t.main).frame(width: 11, height: 11)
                            MarkerDot().fill(t.sub).frame(width: 11, height: 11)
                            MarkerDot().fill(t.error).frame(width: 11, height: 11)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(t.bg)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.subAlt, lineWidth: 1))
            .markerLoop(selected, seed: name, color: theme.main, pad: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Match score

struct ScoreInfoView: View {
    var inSheet = false
    @Environment(\.theme) private var theme
    @Environment(VoiceProfile.self) private var voice

    private var tunedNote: some View {
        Text(voice.result.map { "Tuned to your voice: your voice check (\($0.date.formatted(date: .abbreviated, time: .omitted))) showed how often each model is really right when it's sure, and the score uses that." }
             ?? "Run a voice check (Settings → speech) to tune the score to your voice, so 85 means about 85% of your words are right.")
            .font(.ui(16)).foregroundStyle(theme.main)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Page(title: "match score", showsDone: inSheet) {
                para("While it listens, the speech model is picking each word from its options and knows how sure it is about every pick. The match score is the average of that certainty across your words, from 0 to 100.")
                PageSection(label: "what it means") {
                    tier("85–100", "high", "almost certainly what you said", theme.main)
                    tier("65–84", "check", "mostly right; give it a glance", theme.text)
                    tier("under 65", "low", "noisy room or mumbled; read it before sending", theme.error)
                }
                para("Words the model was unsure about (under 50%) get a dotted underline, so you know where to look.")
                tunedNote
                para("It's a guide, not a guarantee. The model can be confidently wrong, especially with names or rare words, and Whisper and Parakeet measure certainty a bit differently, so their scores aren't directly comparable.")
        }
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.ui(16)).foregroundStyle(theme.text.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tier(_ range: String, _ label: String, _ meaning: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(range).font(.mono(13)).foregroundStyle(theme.sub).frame(width: 74, alignment: .leading)
            Text(label).font(.mono(13, .semibold)).foregroundStyle(color).frame(width: 46, alignment: .leading)
            Text(meaning).font(.ui(15)).foregroundStyle(theme.text)
        }
    }
}
