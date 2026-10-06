import SwiftUI

struct HomeView: View {
    @Environment(Dictator.self) private var dictator
    @Environment(ModelStore.self) private var models
    @Environment(KeyboardSession.self) private var keyboard
    @Environment(\.theme) private var theme
    @State private var sheet: Sheet?
    @State private var showScoreInfo = false
    @State private var editing = false

    enum Sheet: String, Identifiable {
        case history, settings, models
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var dictator = dictator
        VStack(spacing: 0) {
            topBar
            if keyboard.active { keyboardStrip }
            GeometryReader { geo in
                ScrollView {
                    middle
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        // The hint and the recording sit in the middle of the screen; a finished note starts at the top.
                        .frame(maxWidth: .infinity, minHeight: geo.size.height,
                               alignment: centered ? .leading : .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if !editing {
                if dictator.phase == .idle, let latest = dictator.latest { resultBar(latest) }
                bottom
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .history: HistoryView()
                case .settings: SettingsView()
                case .models: NavigationStack { ModelsView(inSheet: true) }
                }
            }
            .environment(\.theme, theme)
            .tint(sheet == .history ? theme.text : theme.main)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .sheet(isPresented: $showScoreInfo) {
            NavigationStack { ScoreInfoView(inSheet: true) }.environment(\.theme, theme).tint(theme.main).presentationDetents([.medium, .large])
        }
        .onChange(of: dictator.latest?.id) { _, _ in editing = false }
        .onChange(of: dictator.showModelPicker) { _, show in
            if show { sheet = .models; dictator.showModelPicker = false }
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 0) {
            if keyboard.showBackHint {
                BackHint().padding(.leading, 14)
            } else {
                HStack(spacing: 2) {
                    Text("utter").foregroundStyle(theme.text)
                    Text(".").foregroundStyle(theme.main)
                }
                .font(.mono(20, .semibold))
                .padding(.leading, 24)
            }
            Spacer()
            IconButton(systemName: "clock.arrow.circlepath", label: "History") { sheet = .history }
            IconButton(systemName: "slider.horizontal.3", label: "Settings") { sheet = .settings }
                .padding(.trailing, 12)
        }
        .frame(height: 56)
    }

    /// While the keyboard session runs: what it's doing, and how to end it.
    private var keyboardStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MarkerDot().fill(keyboard.state == .listening ? theme.error : theme.main).frame(width: 10, height: 10)
                Text(keyboardLine).font(.mono(13)).foregroundStyle(theme.text)
                Spacer()
                Button("end") { keyboard.end() }.font(.mono(13)).foregroundStyle(theme.sub)
            }
        }
        .padding(12)
        .background(theme.subAlt.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private var keyboardLine: String {
        switch keyboard.state {
        case .listening: "keyboard: listening"
        case .writing: "keyboard: writing it down…"
        default: "keyboard is ready"
        }
    }

    // MARK: Middle

    private var centered: Bool {
        dictator.phase != .idle || (dictator.latest == nil && models.hasAnyModel)
    }

    /// While working, a quiet note of which model is listening. Otherwise it only shows in Settings.
    @ViewBuilder private var modelLine: some View {
        if models.isLoading {
            ModelLoading().padding(.top, 6)
        } else {
            Text("using \(models.selected?.name.lowercased() ?? "no model")")
                .font(.mono(12))
                .foregroundStyle(theme.sub.opacity(0.7))
        }
    }

    @ViewBuilder private var middle: some View {
        switch dictator.phase {
        case .recording(let since):
            VStack(alignment: .leading, spacing: 16) {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let left = Recorder.maxSeconds - context.date.timeIntervalSince(since)
                    HStack(spacing: 10) {
                        Text(clock(context.date.timeIntervalSince(since)))
                            .foregroundStyle(theme.sub)
                        // The last two minutes count down, so a long take never ends by surprise.
                        if left <= 120 {
                            Text("· \(clock(max(0, left))) left")
                                .foregroundStyle(theme.error)
                                .markerUnderline(left <= 60, seed: "left", color: theme.error)
                        }
                    }
                    .font(.mono(15))
                }
                Waveform(levels: dictator.levels)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("listening… tap stop when you're done")
                        .font(.mono(13))
                        .foregroundStyle(theme.sub)
                    modelLine
                }
            }
        case .transcribing:
            VStack(alignment: .leading, spacing: 12) {
                if models.isLoading {
                    ModelLoading()
                } else {
                    MarkerSpinner()
                    Text("writing it down…")
                        .font(.mono(13))
                        .foregroundStyle(theme.sub)
                    modelLine
                }
            }
        case .idle:
            if let latest = dictator.latest {
                result(latest)
            } else if !models.hasAnyModel {
                firstRun
            } else if !keyboard.active {
                hint   // during a keyboard session the strip at the top says what's happening
            }
        }
    }

    private func result(_ dictation: Dictation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = dictation.title, !editing {
                Text(title.lowercased())
                    .font(.mono(14, .semibold))
                    .foregroundStyle(theme.sub)
                    .transition(.opacity)
            }
            if dictator.tidyingID == dictation.id {
                HStack(spacing: 10) {
                    MarkerSpinner()
                    Text("tidying…").font(.mono(13)).foregroundStyle(theme.sub)
                }
            }
            EditableTranscript(dictation: dictation, onSave: dictator.saveEdit, isEditing: $editing)
                .opacity(dictator.tidyingID == dictation.id ? 0.4 : 1)
            if let fix = dictator.suggestedFix, !editing { fixOffer(fix) }
            if let message = dictator.message { messageText(message) }
        }
    }

    /// Score and actions, pinned above the mic so they stay in reach on long notes.
    private func resultBar(_ dictation: Dictation) -> some View {
        ResultActions(dictation: dictation, onScoreInfo: { showScoreInfo = true }) {
            Button { withAnimation { dictator.clearLatest() } } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Clear")
        }
    }

    /// "Always write Vox2 when it hears vox two?" after you fix one word.
    private func fixOffer(_ fix: (heard: String, write: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("always write ").foregroundStyle(theme.sub)
             + Text(fix.write).foregroundStyle(theme.text).bold()
             + Text(" when it hears ").foregroundStyle(theme.sub)
             + Text(fix.heard).foregroundStyle(theme.text).bold()
             + Text("?").foregroundStyle(theme.sub))
                .font(.mono(13))
            HStack(spacing: 20) {
                Button { withAnimation { dictator.rememberSuggestedFix() } } label: {
                    Text("add to dictionary").font(.mono(13, .semibold))
                }
                .buttonStyle(SwipeButtonStyle())
                Button("not now") { withAnimation { dictator.suggestedFix = nil } }
                    .font(.mono(13)).foregroundStyle(theme.sub)
            }
        }
        .padding(12)
        .background(theme.subAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("tap the button and talk")
            Text("when you stop, the text is copied, ready to paste anywhere")
                .foregroundStyle(theme.sub)
            if models.isLoading {
                ModelLoading().padding(.top, 16)
            }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                if CaptureInbox.isCapturing {
                    // screen recording mode is running
                    Text("listening to your phone… stop screen recording when you're done, then come back")
                        .font(.mono(13)).foregroundStyle(theme.main)
                        .padding(.top, 18)
                }
            }
            if let message = dictator.message { messageText(message).padding(.top, 8) }
        }
        .font(.mono(15))
        .foregroundStyle(theme.text)
        .padding(.bottom, 40)
    }

    private var firstRun: some View {
        let pick = Catalog.models.first(where: \.recommended)!
        return VStack(alignment: .leading, spacing: 12) {
            Text("first, a speech model.")
                .font(.mono(17, .semibold))
                .foregroundStyle(theme.text)
            Text("Utter turns your voice into text right on this iPhone, so it needs a model downloaded once. After that it works offline.")
                .font(.ui(16))
                .foregroundStyle(theme.sub)
            ModelRow(model: pick)
                .padding(14)
                .background(theme.subAlt, in: RoundedRectangle(cornerRadius: 12))
            Button("see all models") { sheet = .models }
                .font(.mono(14))
            if let error = models.loadError { messageText(error) }
        }
        .padding(.top, 16)
    }

    private func messageText(_ text: String) -> some View {
        Text(text)
            .font(.mono(13))
            .foregroundStyle(theme.error)
    }

    // MARK: Bottom

    /// The marker dot: tap to start, tap again to stop.
    private var bottom: some View {
        let recording = dictator.isRecording
        let busy = dictator.phase == .transcribing || editing
        return Button { dictator.toggle() } label: {
            ZStack {
                // the site's hand-drawn marker dot, with a soft drop under it
                MarkerDot()
                    .fill(Color.black.opacity(0.16))
                    .offset(y: 4)
                MarkerDot()
                    .fill(recording ? theme.error : theme.main)
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(theme.bg)
            }
            .frame(width: 104, height: 104)
            .rotationEffect(.degrees(recording ? Double(dictator.level) * 8 - 4 : 0))
            .scaleEffect(recording ? 1 + CGFloat(dictator.level) * 0.1 : 1)
            .animation(.easeOut(duration: 0.12), value: dictator.level)
            .animation(.spring(duration: 0.3), value: recording)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.4 : 1)
        .accessibilityLabel(recording ? "Stop dictating" : "Start dictating")
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Points at iOS's own "◀ Notes" link at the top left, the only way back to the app you came from.
/// Apps can't jump back by themselves, so this just makes that link hard to miss.
private struct BackHint: View {
    @Environment(\.theme) private var theme
    @State private var nudge = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            MarkerArrow()
                .stroke(theme.main, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 30)
                .offset(x: nudge ? -3 : 1, y: nudge ? -4 : 1)
            Text("back to your app")
                .font(.mono(13))
                .foregroundStyle(theme.text)
                .padding(.bottom, 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudge = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("To go back, tap the back link at the top left of the screen")
    }
}
