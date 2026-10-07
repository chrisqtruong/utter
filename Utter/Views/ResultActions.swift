import SwiftUI

/// The score line and the actions for one dictation: the same on home and in history,
/// plain words in theme colors so they read in every theme.
struct ResultActions<Trailing: View>: View {
    let dictation: Dictation
    let onScoreInfo: () -> Void
    @ViewBuilder let trailing: Trailing
    @Environment(Dictator.self) private var dictator
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // what the model thought of it
            Button(action: onScoreInfo) {
                HStack(spacing: 6) {
                    Text("match").foregroundStyle(theme.sub)
                    ScoreChip(transcript: dictation.transcript)
                    if let change = dictation.changeLabel { Text("· \(change)").foregroundStyle(theme.sub) }
                }
                .font(.mono(13))
                .lineLimit(1)
            }
            // what you can do with it
            HStack(spacing: 20) {
                let copied = dictator.copiedID == dictation.id
                Button { dictator.copy(dictation) } label: {
                    Text(copied ? "copied" : "copy").foregroundStyle(copied ? theme.main : theme.sub)
                }
                .accessibilityLabel(copied ? "Copied. Copy again" : "Copy")
                // one careful pass is enough (the score line says "tidied"); undo brings the button back
                if !dictation.isTidied, dictation.canTidy {
                    // only offered when tidy would actually change something
                    Button { Task { await dictator.tidy(dictation) } } label: { Text("tidy") }
                        .disabled(dictator.tidyingID != nil)
                        .accessibilityHint("Fixes punctuation and drops false starts, on this iPhone")
                }
                if dictation.canUndo {
                    Button { dictator.undo(dictation) } label: { Text("undo") }
                        .accessibilityHint("Steps back one change, back to what you said")
                }
                ShareLink(item: dictation.text) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
                Spacer(minLength: 8)
                trailing
            }
            .font(.mono(14))
            .foregroundStyle(theme.sub)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(theme.subAlt).frame(height: 1) }
    }
}
