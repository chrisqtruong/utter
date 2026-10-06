import SwiftUI

/// Shows a dictation's text; tap it to fix a word or two.
struct EditableTranscript: View {
    let dictation: Dictation
    let onSave: (String) -> Void
    @Binding var isEditing: Bool
    @Environment(\.theme) private var theme
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.transcript)
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .lineSpacing(5)
                    .focused($focused)
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(theme.subAlt, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 20) {
                    Button { save() } label: { Text("done").font(.mono(15, .semibold)) }
                        .buttonStyle(SwipeButtonStyle())
                    Button("cancel") { isEditing = false }
                        .font(.mono(14))
                        .foregroundStyle(theme.sub)
                    Spacer()
                    if dictation.isEdited {
                        Button("back to what you said") { draft = dictation.transcript.text }
                            .font(.mono(12))
                            .foregroundStyle(theme.sub)
                    }
                }
            } else {
                Group {
                    if dictation.isEdited {
                        Text(dictation.text)
                            .font(.transcript)
                            .foregroundStyle(theme.text)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TranscriptText(transcript: dictation.transcript, selectable: false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { startEditing() }
                .accessibilityAction(named: "Edit") { startEditing() }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing { draft = dictation.text; focused = true }
        }
    }

    private func startEditing() {
        draft = dictation.text
        isEditing = true
        focused = true
    }

    private func save() {
        onSave(draft)
        isEditing = false
    }
}

/// A rough highlighter swipe behind the label, like the site's header links.
struct SwipeButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                MarkerSwipe()
                    .fill(theme.main.opacity(configuration.isPressed ? 0.6 : 0.4))
                    .rotationEffect(.degrees(-1.2))
            }
            .contentShape(Rectangle())
    }
}
