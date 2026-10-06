import SwiftUI

/// Your fixes for names and words the model gets wrong.
struct DictionaryView: View {
    @Environment(Vocabulary.self) private var vocabulary
    @Environment(\.theme) private var theme
    @State private var heard = ""
    @State private var write = ""
    @State private var editingID: UUID?
    @FocusState private var focus: Field?

    enum Field { case heard, write }

    var body: some View {
        Page(title: "dictionary", showsDone: false) {
            Text("Teach Utter names and words it gets wrong. When it writes the left side, you get the right side.")
                .font(.ui(16)).foregroundStyle(theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            PageSection(label: editingID == nil ? "add a fix" : "change this fix") {
                HStack(spacing: 10) {
                    field("it writes", text: $heard, example: "vox two", which: .heard)
                    Text("→").font(.mono(17)).foregroundStyle(theme.main)
                    field("you want", text: $write, example: "Vox2", which: .write)
                }
                HStack(spacing: 20) {
                    Button { save() } label: { Text(editingID == nil ? "add" : "save").font(.mono(15, .semibold)) }
                        .buttonStyle(SwipeButtonStyle())
                        .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty || write.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editingID != nil {
                        Button("cancel") { clear() }.font(.mono(14)).foregroundStyle(theme.sub)
                    }
                }
            }

            PageSection(label: vocabulary.entries.isEmpty ? "your words" : "your words · \(vocabulary.entries.count)",
                        note: "Tip: fix a single word in a dictation and Utter offers to add it here. Whisper also uses these words to spell names right the first time.") {
                if vocabulary.entries.isEmpty {
                    Text("Nothing yet. Good first ones: names of people and places, brands, and words from other languages.")
                        .font(.ui(15)).foregroundStyle(theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(vocabulary.entries) { entry in row(entry) }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, example: String, which: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(11)).foregroundStyle(theme.sub)
            TextField(example, text: text)
                .font(.ui(17))
                .foregroundStyle(theme.text)
                .textInputAutocapitalization(which == .heard ? .never : .sentences)
                .autocorrectionDisabled()
                .focused($focus, equals: which)
                .submitLabel(which == .heard ? .next : .done)
                .onSubmit { if which == .heard { focus = .write } else { save() } }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(theme.subAlt, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ entry: Vocabulary.Entry) -> some View {
        HStack(spacing: 10) {
            Button {
                editingID = entry.id; heard = entry.heard; write = entry.write; focus = .write
            } label: {
                HStack(spacing: 10) {
                    Text(entry.heard).foregroundStyle(theme.sub).strikethrough(color: theme.sub.opacity(0.5))
                    Text("→").font(.mono(14)).foregroundStyle(theme.main)
                    Text(entry.write).foregroundStyle(theme.text)
                    Spacer()
                }
                .font(.ui(17))
                .lineLimit(1)
                .contentShape(Rectangle())
                .markerUnderline(editingID == entry.id, seed: entry.write, color: theme.main)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.heard) becomes \(entry.write). Double-tap to change")
            Button { withAnimation { vocabulary.remove(entry.id); if editingID == entry.id { clear() } } } label: {
                Image(systemName: "xmark").font(.ui(13, weight: .semibold)).foregroundStyle(theme.sub)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Remove \(entry.heard)")
        }
    }

    private func save() {
        guard vocabulary.save(heard: heard, write: write, replacing: editingID) else { return }
        Haptics.tap()
        clear()
    }

    private func clear() {
        heard = ""; write = ""; editingID = nil; focus = nil
    }
}
