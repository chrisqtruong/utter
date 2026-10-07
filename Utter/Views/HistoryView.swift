import SwiftUI

struct HistoryView: View {
    /// One list of places for the whole stack (notes and the archive), so they never get mixed up.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HistoryList(archive: false, openArchive: { path.append(ArchiveRoute()) })
                .navigationDestination(for: Dictation.self) { DictationDetail(item: $0) }
                .navigationDestination(for: ArchiveRoute.self) { _ in HistoryList(archive: true) }
        }
    }
}

private struct ArchiveRoute: Hashable {}

/// History, or the archive: the same list, search, filters and select mode.
/// Swipe right to archive (or unarchive) or copy; swipe left to delete, after asking.
struct HistoryList: View {
    let archive: Bool
    var openArchive: () -> Void = {}
    @Environment(History.self) private var history
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var range: DateRange = .all
    @State private var pickedDay = Date()
    @State private var showDayPicker = false
    @State private var confirmClear = false
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmDelete: Set<UUID>?
    @State private var importingFile = false
    @State private var broadcastTrigger = 0
    @Environment(Dictator.self) private var dictator

    enum DateRange: Hashable {
        case all, today, week, month, day(Date)

        var label: String {
            switch self {
            case .all: "all"
            case .today: "today"
            case .week: "this week"
            case .month: "this month"
            case .day(let d): d.formatted(.dateTime.month(.abbreviated).day()).lowercased()
            }
        }

        func contains(_ date: Date) -> Bool {
            let cal = Calendar.current
            switch self {
            case .all: return true
            case .today: return cal.isDateInToday(date)
            case .week: return cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
            case .month: return cal.isDate(date, equalTo: .now, toGranularity: .month)
            case .day(let d): return cal.isDate(date, inSameDayAs: d)
            }
        }
    }

    private var filtered: [Dictation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return pool.filter { item in
            range.contains(item.date) && (query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
                                           || (item.title?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    /// history shows what isn't archived; the archive shows what is
    private var pool: [Dictation] { history.items.filter { $0.isArchived == archive } }

    private var days: [(String, [Dictation])] {
        var out: [(String, [Dictation])] = []
        for item in filtered {
            let label = item.date.dayLabel
            if out.last?.0 == label { out[out.count - 1].1.append(item) } else { out.append((label, [item])) }
        }
        return out
    }

    var body: some View {
            Group {
                if pool.isEmpty && (archive || history.archivedCount == 0) {
                    ContentUnavailableView {
                        Label(archive ? "Nothing archived" : "Nothing yet", systemImage: archive ? "archivebox" : "text.bubble")
                    } description: {
                        Text(archive ? "Swipe right on a note in history to archive it." : "Your dictations show up here. Only the text is kept, never the recording.")
                    }
                    .foregroundStyle(theme.sub)
                } else {
                    List(selection: $selection) {
                        if days.isEmpty {
                            Text(pool.isEmpty ? "Everything's archived." : search.isEmpty ? "Nothing from \(range.label)." : "No dictations match “\(search)”.")
                                .foregroundStyle(theme.sub)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(days, id: \.0) { day, items in
                            Section {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        HistoryRow(item: item, highlight: search,
                                                   onArchive: { withAnimation { history.setArchived([item.id], !archive) } },
                                                   onDelete: { confirmDelete = [item.id] })
                                    }
                                    .themedRow(theme)
                                }
                            } header: {
                                HStack {
                                    SectionLabel(text: day)
                                    Spacer()
                                    SectionLabel(text: "\(items.count)")
                                }
                            }
                        }
                    }
                    .listSectionSpacing(.compact)
                    .contentMargins(.top, 4, for: .scrollContent)
                    // The date filters sit right under the search field, always in view.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        filterBar.background(theme.bg)
                    }
                    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: archive ? "Search the archive" : "Search your words")
                    .environment(\.editMode, .constant(selecting ? .active : .inactive))
                    .safeAreaInset(edge: .bottom, spacing: 0) { if selecting { selectionBar } }
                }
            }
            .themedList(theme)
            .navigationTitle(archive ? "Archive" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ArchiveBack(on: archive && !selecting))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !selecting && !archive {
                        Menu {
                            Button("Transcribe a file", systemImage: "doc.badge.plus") { importingFile = true }
                            Button("Transcribe what's playing", systemImage: "play.rectangle") { broadcastTrigger += 1 }
                            if history.archivedCount > 0 {
                                Button("Archive · \(history.archivedCount)", systemImage: "archivebox") { openArchive() }
                            }
                            if !history.items.isEmpty {
                            Divider()
                            Button("Select", systemImage: "checkmark.circle") { withAnimation { selecting = true } }
                            ShareLink(item: HistoryExport(items: filtered),
                                      preview: SharePreview("Utter notes", image: Image(systemName: "doc.text"))) {
                                Label(isFiltered ? "Export these \(filtered.count) as text" : "Export all as text",
                                      systemImage: "square.and.arrow.up")
                            }
                            if isFiltered && !filtered.isEmpty {
                                Button("Delete these \(filtered.count)", systemImage: "trash", role: .destructive) {
                                    confirmDelete = Set(filtered.map(\.id))
                                }
                            }
                            Button("Clear all history", systemImage: "trash", role: .destructive) { confirmClear = true }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .noGlass()
                ToolbarItem(placement: .confirmationAction) {
                    if selecting {
                        Button("Cancel") { withAnimation { selecting = false; selection = [] } }
                    } else if archive {
                        if !pool.isEmpty { Button("Select") { withAnimation { selecting = true } } }
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
                .noGlass()
            }
            .confirmationDialog("Clear all \(history.items.count) dictations?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear all", role: .destructive) { history.clear() }
            } message: {
                Text("This can't be undone, and it includes the archive. Export them first if you want a copy.")
            }
            .confirmationDialog(confirmDelete?.count == 1 ? "Delete this note?" : "Delete \(confirmDelete?.count ?? 0) notes?",
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let ids = confirmDelete { history.delete(ids) }
                    selection = []; selecting = false; confirmDelete = nil
                }
            } message: {
                Text("This can't be undone.")
            }
            .sheet(isPresented: $showDayPicker) { dayPicker }
            // iOS's screen recording prompt, opened from the menu
            .background(BroadcastPicker(trigger: broadcastTrigger).frame(width: 1, height: 1))
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.audio, .movie]) { result in
                guard case .success(let url) = result else { return }
                dismiss()   // back home, where the text shows up
                Task { await dictator.transcribeFile(url) }
            }
    }

    private var isFiltered: Bool { range != .all || !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// While selecting: pick all shown, then archive (or unarchive) or delete the chosen ones.
    private var selectionBar: some View {
        HStack {
            let allShown = Set(filtered.map(\.id))
            Button(selection == allShown ? "select none" : "select all \(filtered.count)") {
                selection = selection == allShown ? [] : allShown
            }
            .font(.mono(14)).foregroundStyle(theme.sub)
            Spacer()
            Button {
                withAnimation { history.setArchived(selection, !archive) }
                selection = []; selecting = false
            } label: {
                Text(archive ? "unarchive" : "archive").font(.mono(15))
            }
            .foregroundStyle(theme.text)
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)
            .padding(.trailing, 14)
            Button { confirmDelete = selection } label: {
                Text(selection.isEmpty ? "delete" : "delete \(selection.count)").font(.mono(15, .semibold))
            }
            .buttonStyle(SwipeButtonStyle())
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(theme.subAlt).frame(height: 1) }
    }

    /// all · today · this week · this month · pick a day. The chosen one gets a marker loop.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach([DateRange.all, .today, .week, .month], id: \.self) { option in
                    chip(option.label, selected: range == option) { range = option }
                }
                if case .day = range {
                    chip(range.label, selected: true) { showDayPicker = true }
                } else {
                    Button { showDayPicker = true } label: {
                        Image(systemName: "calendar").font(.ui(15))
                            .frame(width: 32, height: 28).contentShape(Rectangle())
                    }
                    .foregroundStyle(theme.sub)
                    .accessibilityLabel("Pick a day")
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(13, selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.text : theme.sub)
                .markerLoop(selected, seed: text, color: theme.main, pad: 5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dayPicker: some View {
        NavigationStack {
            DatePicker("Day", selection: $pickedDay, in: (history.items.last?.date ?? .now)...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Pick a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDayPicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show") { range = .day(pickedDay); showDayPicker = false }
                    }
                }
                .background(theme.bg.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .tint(theme.main)
    }
}

private struct HistoryRow: View {
    let item: Dictation
    var highlight = ""
    var onArchive: () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(\.theme) private var theme

    /// The text with your search words highlighted.
    private var text: AttributedString {
        var out = AttributedString(item.text)
        let query = highlight.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return out }
        var from = out.startIndex
        while from < out.endIndex, let r = out[from...].range(of: query, options: .caseInsensitive) {
            out[r].backgroundColor = theme.main.opacity(0.35)
            from = r.upperBound
        }
        return out
    }

    private var meta: Text {
        let score = item.transcript.score
        let tier = ScoreTier(score)
        let scoreColor: Color = tier == .high ? theme.main : tier == .moderate ? theme.text : theme.error
        var parts = [Text(item.date.shortTime)]
        if let source = item.source {
            let short = source.count > 24 ? String(source.prefix(10)) + "…" + String(source.suffix(10)) : source
            parts.append(Text(short.lowercased()))
        }
        parts.append(Text("\(score)").foregroundStyle(scoreColor).fontWeight(.semibold))
        parts.append(Text(item.modelName.lowercased()))
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = item.title {
                Text(title.lowercased()).font(.mono(13, .semibold)).foregroundStyle(theme.text)
            }
            Text(text)
                .font(.ui(16))
                .foregroundStyle(theme.text)
                .lineLimit(3)
            // one line of text, so at big text sizes it wraps between words instead of mid-word
            meta
            .font(.mono(12))
            .foregroundStyle(theme.sub)
        }
        .padding(.vertical, 4)
        // swipe right: archive (a full swipe) or copy. swipe left: delete, after asking.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(item.isArchived ? "Unarchive" : "Archive", systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox") {
                onArchive()
                Haptics.tap()
            }
            .tint(theme.main)
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.text
                Haptics.tap()
            }
            .tint(theme.sub)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash") { onDelete() }
                .tint(theme.error)
        }
    }
}

struct DictationDetail: View {
    let item: Dictation
    @Environment(History.self) private var history
    @Environment(Dictator.self) private var dictator
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showScoreInfo = false
    @State private var editing = false
    @State private var confirmDelete = false

    /// The live copy from history, so edits show up right away.
    private var current: Dictation { history.items.first { $0.id == item.id } ?? item }

    var body: some View {
        let item = current
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let title = item.title {
                    Text(title.lowercased()).font(.mono(15, .semibold)).foregroundStyle(theme.sub)
                }
                if dictator.tidyingID == item.id {
                    HStack(spacing: 10) {
                        MarkerSpinner()
                        Text("tidying…").font(.mono(13)).foregroundStyle(theme.sub)
                    }
                }
                EditableTranscript(dictation: item, onSave: { history.edit(item.id, to: $0) }, isEditing: $editing)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.date.dayLabel), \(item.date.shortTime)")
                    Text("\(item.transcript.words.count) words · \(Int(item.seconds.rounded()))s · \(item.modelName.lowercased())")
                    if let source = item.source { Text("from \(source)") }
                }
                .font(.mono(12))
                .foregroundStyle(theme.sub)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(theme.bg.ignoresSafeArea())
        .handDrawnBack()
        .onAppear { dictator.checkTidy(current) }
        .onChange(of: current.text) { _, _ in dictator.checkTidy(current) }
        // the same score line and actions as home, pinned at the bottom
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !editing {
                ResultActions(dictation: item, onScoreInfo: { showScoreInfo = true }) {
                    Button {
                        history.setArchived([item.id], !item.isArchived)
                        Haptics.tap()
                        dismiss()
                    } label: { Image(systemName: item.isArchived ? "tray.and.arrow.up" : "archivebox") }
                        .accessibilityLabel(item.isArchived ? "Unarchive" : "Archive")
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete")
                }
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                history.delete([item.id])
                dismiss()
            }
        } message: { Text("This can't be undone.") }
        .sheet(isPresented: $showScoreInfo) {
            NavigationStack { ScoreInfoView(inSheet: true) }.environment(\.theme, theme).tint(theme.main).presentationDetents([.medium, .large])
        }
    }
}

/// History as one plain-text (Markdown) file, newest first, ready for Notes, Obsidian or Files.
struct HistoryExport: Transferable {
    let items: [Dictation]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Utter notes.md")
            try export.markdown.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    var markdown: String {
        var out = "# Utter notes\n"
        var lastDay = ""
        for item in items {
            let day = item.date.formatted(date: .complete, time: .omitted)
            if day != lastDay { out += "\n## \(day)\n"; lastDay = day }
            out += "\n### \(item.date.shortTime)\(item.title.map { " · \($0)" } ?? "")\n\n\(item.text)\n"
        }
        return out
    }
}

/// The archive gets the hand-drawn back arrow; history itself is a sheet with Done.
private struct ArchiveBack: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.handDrawnBack() } else { content }
    }
}
