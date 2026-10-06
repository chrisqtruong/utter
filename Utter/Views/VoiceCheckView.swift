import SwiftUI

/// Read a short passage and your names once; see which model hears you best,
/// teach it your names, and tune the match score to your voice.
struct VoiceCheckView: View {
    @Environment(ModelStore.self) private var models
    @Environment(Vocabulary.self) private var vocabulary
    @Environment(VoiceProfile.self) private var profile
    @Environment(\.theme) private var theme

    enum Step { case intro, reading, checking, done }
    @State private var step: Step = .intro
    @State private var names: [String] = []
    @State private var newName = ""
    @State private var recorder = Recorder()
    @State private var levels: [Float] = Array(repeating: 0, count: 40)
    @State private var startedAt = Date()
    @State private var progress = ""
    @State private var runs: [VoiceCheck.ModelRun] = []
    @State private var mic = ""
    @State private var added: [Vocabulary.Entry] = []
    @State private var problem: String?

    private var downloaded: [SpeechModel] { Catalog.models.filter { models.status[$0.id] == .ready } }

    var body: some View {
        Page(title: "voice check", showsDone: false) {
            switch step {
            case .intro: intro
            case .reading: reading
            case .checking: checking
            case .done: results
            }
        }
        .onAppear { if names.isEmpty { names = profile.names.isEmpty ? Array(vocabulary.hintWords.prefix(8)) : profile.names } }
        .onDisappear { if step == .reading { _ = recorder.stop() } }
    }

    // MARK: 1 · intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Read a short passage and a few names out loud, about a minute. Utter will:")
                    .font(.ui(17)).foregroundStyle(theme.text)
                bullet("find which of your models hears you best")
                bullet("add names it gets wrong to your dictionary")
                bullet("tune the match score to your voice and mic")
                Text("The recording is thrown away as soon as it's checked.")
                    .font(.ui(14)).foregroundStyle(theme.sub)
            }

            if let result = profile.result {
                PageSection(label: "last time") {
                    Text("\(profile.lastRunLabel ?? "") · \(result.models.map { "\($0.name.lowercased()) \(Int(($0.accuracy * 100).rounded()))%" }.joined(separator: " · "))")
                        .font(.mono(13)).foregroundStyle(theme.sub)
                }
            }

            PageSection(label: "names you say often",
                        note: "People, places, brands, words from other languages. Optional, but this is where it helps most.") {
                namesEditor
            }

            if downloaded.isEmpty {
                Text("Download a speech model first (Settings → Model).").font(.mono(13)).foregroundStyle(theme.error)
            } else {
                Button { begin() } label: { Text("start reading").font(.mono(16, .semibold)) }
                    .buttonStyle(SwipeButtonStyle())
                if downloaded.count > 1 {
                    Text("It will test all \(downloaded.count) of your downloaded models.")
                        .font(.ui(14)).foregroundStyle(theme.sub)
                }
            }
            if let problem { Text(problem).font(.mono(13)).foregroundStyle(theme.error) }
        }
    }

    private var namesEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("add a name", text: $newName)
                    .font(.ui(17)).foregroundStyle(theme.text)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addName)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(theme.subAlt, in: RoundedRectangle(cornerRadius: 10))
                Button("add", action: addName).font(.mono(14, .semibold)).buttonStyle(SwipeButtonStyle())
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !names.isEmpty {
                FlowRow(names, spacing: 8) { name in
                    Button { names.removeAll { $0 == name } } label: {
                        HStack(spacing: 6) {
                            Text(name).font(.ui(15)).foregroundStyle(theme.text)
                            Image(systemName: "xmark").font(.ui(10, weight: .bold)).foregroundStyle(theme.sub)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.subAlt, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(name)")
                }
            }
        }
    }

    private func addName() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !names.contains(name), names.count < 12 else { newName = ""; return }
        names.append(name)
        newName = ""
    }

    // MARK: 2 · reading

    private var reading: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Read this at your normal pace:").font(.mono(13)).foregroundStyle(theme.sub)
            Text(VoiceCheck.passage)
                .font(.ui(21)).foregroundStyle(theme.text).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            if !names.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Then say these names:").font(.mono(13)).foregroundStyle(theme.sub)
                    Text(names.joined(separator: ", "))
                        .font(.ui(21, weight: .semibold)).foregroundStyle(theme.text)
                }
            }
            Waveform(levels: levels).frame(maxWidth: .infinity)
            HStack(spacing: 18) {
                Button { finish() } label: {
                    ZStack {
                        MarkerDot().fill(theme.error)
                        Image(systemName: "stop.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(theme.bg)
                    }
                    .frame(width: 68, height: 68)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done reading")
                TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("tap when you're done").font(.mono(13)).foregroundStyle(theme.sub)
                        Text(clock(ctx.date.timeIntervalSince(startedAt))).font(.mono(13)).foregroundStyle(theme.sub.opacity(0.7))
                    }
                }
                Spacer()
                Button("start over") { _ = recorder.stop(); step = .intro }
                    .font(.mono(13)).foregroundStyle(theme.sub)
            }
        }
    }

    // MARK: 3 · checking

    private var checking: some View {
        VStack(alignment: .leading, spacing: 14) {
            MarkerSpinner()
            Text(progress).font(.mono(13)).foregroundStyle(theme.sub)
            Text("Loading a model for the first time can take a moment.").font(.ui(14)).foregroundStyle(theme.sub.opacity(0.8))
        }
        .padding(.top, 40)
    }

    // MARK: 4 · results

    private var results: some View {
        let best = runs.max { $0.accuracy < $1.accuracy }
        return VStack(alignment: .leading, spacing: 32) {
            PageSection(label: "how well each model heard you") {
                ForEach(runs, id: \.model.id) { run in
                    let isBest = run.model.id == best?.model.id && runs.count > 1
                    HStack(alignment: .firstTextBaseline) {
                        Text(run.model.name.lowercased())
                            .font(.ui(17, weight: isBest ? .semibold : .regular)).foregroundStyle(theme.text)
                            .markerUnderline(isBest, seed: "best", color: theme.main)
                        if models.selectedID == run.model.id { Text("in use").font(.mono(11)).foregroundStyle(theme.sub) }
                        Spacer()
                        Text("\(Int((run.accuracy * 100).rounded()))% of words right")
                            .font(.mono(13)).foregroundStyle(isBest ? theme.main : theme.sub)
                    }
                }
                if let best, runs.count > 1, best.model.id != models.selectedID {
                    Button { models.select(best.model) } label: { Text("use \(best.model.name.lowercased())").font(.mono(14, .semibold)) }
                        .buttonStyle(SwipeButtonStyle())
                }
            }

            if !names.isEmpty, let shown = runs.first(where: { $0.model.id == models.selectedID }) ?? best {
                PageSection(label: "your names", note: added.isEmpty ? nil : "Added to your dictionary. Tap × to undo one.") {
                    ForEach(shown.names, id: \.name) { nameRow($0) }
                }
            }

            PageSection(label: "your mic") {
                Text(mic).font(.ui(16)).foregroundStyle(theme.text)
            }

            Text("The match score is now tuned to your voice. Run this again if you change mics, rooms, or models.")
                .font(.ui(14)).foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            Button("check again") { step = .intro }.font(.mono(13)).foregroundStyle(theme.sub)
        }
    }

    @ViewBuilder private func nameRow(_ r: VoiceCheck.NameResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(r.name).font(.ui(17, weight: .semibold)).foregroundStyle(theme.text)
            switch r.outcome {
            case .right:
                Text("heard right").font(.mono(12)).foregroundStyle(theme.main)
            case .fixable(let heard):
                Text("heard “\(heard)”").font(.mono(12)).foregroundStyle(theme.sub)
                Spacer()
                if let entry = added.first(where: { $0.write == r.name }) {
                    Button {
                        vocabulary.remove(entry.id)
                        added.removeAll { $0.id == entry.id }
                    } label: {
                        HStack(spacing: 4) {
                            Text("fixed").font(.mono(12)).foregroundStyle(theme.main)
                            Image(systemName: "xmark").font(.ui(10, weight: .bold)).foregroundStyle(theme.sub)
                        }
                    }
                    .accessibilityLabel("Fixed. Double-tap to undo")
                }
            case .tooCommon(let heard):
                Text("heard “\(heard)”, too common to fix automatically").font(.mono(12)).foregroundStyle(theme.sub)
            case .missed:
                Text("not heard").font(.mono(12)).foregroundStyle(theme.sub)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Steps

    private func begin() {
        problem = nil
        profile.names = names
        Task {
            guard await Recorder.requestPermission() else { problem = UtterError.micDenied.errorDescription; return }
            recorder.onLevel = { value in
                Task { @MainActor in levels.removeFirst(); levels.append(value) }
            }
            do {
                try recorder.start()
                startedAt = Date()
                step = .reading
            } catch {
                problem = UtterError.micUnavailable.errorDescription
            }
        }
    }

    private func finish() {
        let (samples, heard) = recorder.stop()
        guard samples.count > 16_000 * 15, heard else {
            problem = "That was a bit short. Read the whole passage, then tap stop."
            step = .intro
            return
        }
        step = .checking
        Task { await check(samples) }
    }

    private func check(_ samples: [Float]) async {
        mic = VoiceCheck.micVerdict(samples)
        var done: [VoiceCheck.ModelRun] = []
        for (i, model) in downloaded.enumerated() {
            progress = "checking with \(model.name.lowercased())… (\(i + 1) of \(downloaded.count))"
            do {
                try await models.engine.load(model)
                // English passage, raw output: no dictionary, so we see what the model really hears.
                let raw = try await models.engine.transcribe(samples, language: "en")
                done.append(VoiceCheck.score(Cleanup.apply(raw, removeFillers: false), model: model, names: names))
            } catch {
                continue
            }
        }
        await models.loadSelected()   // back to the model you use
        guard !done.isEmpty else { problem = "Couldn't check that recording. Try again."; step = .intro; return }

        // Teach the dictionary every fixable name any model got wrong.
        var newEntries: [Vocabulary.Entry] = []
        for run in done {
            for result in run.names {
                guard case .fixable(let heard) = result.outcome,
                      !newEntries.contains(where: { $0.heard.lowercased() == heard.lowercased() }) else { continue }
                if vocabulary.save(heard: heard, write: result.name), let entry = vocabulary.entries.first {
                    newEntries.append(entry)
                }
            }
        }
        added = newEntries
        runs = done
        profile.save(VoiceProfile.Result(
            date: Date(),
            models: done.map { .init(id: $0.model.id, name: $0.model.name, accuracy: $0.accuracy, words: $0.words) },
            calibration: Dictionary(uniqueKeysWithValues: done.map { ($0.model.id, $0.bins) }),
            mic: mic,
            namesLearned: newEntries.count))
        Haptics.tap()
        step = .done
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            MarkerDot().fill(theme.main).frame(width: 8, height: 8)
            Text(text).font(.ui(16)).foregroundStyle(theme.text)
        }
    }

    private func clock(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Lays chips out in rows that wrap.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let content: (Item) -> Content

    init(_ items: [Item], spacing: CGFloat, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items; self.spacing = spacing; self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing) { ForEach(items, id: \.self) { content($0) } }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}
