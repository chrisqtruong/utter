import SwiftUI

// MARK: Type

extension Font {
    /// Labels, numbers and buttons: monospaced, like Vox2.
    /// Sizes map to iOS text styles, so everything follows the iPhone's text size setting.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(textStyle(size), design: .monospaced).weight(weight)
    }
    /// Everything else, in the system font, also following the text size setting.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(size)).weight(weight)
    }
    /// The transcript itself: plain and easy to read.
    static let transcript = Font.system(.title2)

    /// The iOS text style whose default size is closest to `size` points.
    private static func textStyle(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2      // 11
        case ..<12.5: .caption       // 12
        case ..<14: .footnote        // 13
        case ..<15.5: .subheadline   // 15
        case ..<16.5: .callout       // 16
        case ..<18.5: .body          // 17
        case ..<21: .title3          // 20
        case ..<25: .title2          // 22
        default: .title              // 28
        }
    }
}

// MARK: Transcript with shaky words underlined

struct TranscriptText: View {
    let transcript: Transcript
    var font: Font = .transcript
    var selectable = true
    @Environment(\.theme) private var theme
    @AppStorage("showShaky") private var showShaky = true

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(theme.text)
            .lineSpacing(5)
            .modifier(Selectable(on: selectable))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for (i, word) in transcript.words.enumerated() {
            var piece = AttributedString(word.text)
            if showShaky && word.confidence < Transcript.shakyBelow {
                piece.underlineStyle = Text.LineStyle(pattern: .dot, color: theme.error)
                piece.foregroundColor = theme.error
            }
            if i > 0 { out += AttributedString(word.startsParagraph ? "\n\n" : " ") }
            out += piece
        }
        return out
    }
}

// MARK: Score

struct ScoreChip: View {
    let transcript: Transcript
    var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        let tier = ScoreTier(transcript.score)
        HStack(spacing: 6) {
            Text("\(transcript.score)")
                .font(.mono(compact ? 13 : 15, .semibold))
            if !compact {
                Text(tier.label)
                    .font(.mono(13))
            }
        }
        .foregroundStyle(color(tier))
        .accessibilityLabel("Match score \(transcript.score), \(tier.label)")
    }

    private func color(_ tier: ScoreTier) -> Color {
        switch tier {
        case .high: theme.main
        case .moderate: theme.text
        case .low: theme.error
        }
    }
}

// MARK: Waveform

struct Waveform: View {
    let levels: [Float]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(theme.main)
                    .frame(width: 4, height: max(4, CGFloat(levels[i]) * 64))
            }
        }
        .frame(height: 68)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

// MARK: Small pieces

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.ui(18, weight: .medium))
                .foregroundStyle(theme.sub)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// Lowercase section label, Vox2 style.
struct SectionLabel: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text.lowercased())
            .font(.mono(12))
            .foregroundStyle(theme.sub)
            .textCase(nil)
    }
}

extension View {
    /// Themed backdrop for lists and forms.
    func themedList(_ theme: Theme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .toolbarBackground(theme.bg, for: .navigationBar)
    }

    func themedRow(_ theme: Theme) -> some View {
        self.listRowBackground(theme.subAlt)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened).lowercased() }

    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "today" }
        if cal.isDateInYesterday(self) { return "yesterday" }
        let sameYear = cal.isDate(self, equalTo: .now, toGranularity: .year)
        return (sameYear ? formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                         : formatted(.dateTime.month(.abbreviated).day().year())).lowercased()
    }
}

private struct Selectable: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.textSelection(.enabled) } else { content }
    }
}

// MARK: Marker spinner

/// A spinner drawn like the other marks: part of a wobbly marker loop, turning.
struct MarkerSpinner: View {
    var size: CGFloat = 18
    @Environment(\.theme) private var theme
    @State private var spinning = false

    var body: some View {
        MarkerLoop(seed: "spinner", round: true, pad: -2)
            .trim(from: 0, to: 0.72)
            .stroke(theme.main, style: StrokeStyle(lineWidth: max(2, size / 7.5), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
            .accessibilityLabel("Working")
    }
}

/// Shown while the speech model loads: the marker spinner and what it's doing. No fake progress.
struct ModelLoading: View {
    @Environment(ModelStore.self) private var models
    @Environment(\.theme) private var theme

    var body: some View {
        let name = models.selected?.name.lowercased() ?? "model"
        HStack(spacing: 10) {
            MarkerSpinner(size: 16)
            Text(!models.isFirstSetup ? "loading \(name)"
                 : models.isFirstEver ? "setting up \(name) for the first time"
                 : "setting up \(name) after the update")
                .font(.mono(12))
                .foregroundStyle(theme.sub)
        }
        .accessibilityElement(children: .combine)
    }
}
