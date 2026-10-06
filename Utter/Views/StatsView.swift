import SwiftUI

struct StatsView: View {
    @Environment(History.self) private var history
    @Environment(\.theme) private var theme

    var body: some View {
        let stats = Stats(history.items)
        Page(title: "stats", showsDone: false) {
            if stats.dictations == 0 {
                Text("Nothing to count yet. Dictate something and your numbers show up here.")
                    .font(.ui(16)).foregroundStyle(theme.sub)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 26) {
                    tile(stats.words.formatted(), "words dictated")
                    tile(formatMinutes(stats.minutesSaved), "time saved vs typing")
                    tile(stats.dictations.formatted(), "dictations")
                    tile(formatMinutes(stats.secondsSpoken / 60), "time talking")
                    tile("\(stats.speakingWPM)", "words a minute, talking")
                    tile("\(stats.averageScore)", "average match", color: color(ScoreTier(stats.averageScore)))
                    tile("\(stats.streakDays)", stats.streakDays == 1 ? "day streak" : "days in a row")
                    tile(stats.firstDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()).lowercased() } ?? "–", "since")
                }

                PageSection(label: "this week") {
                    WeekStrokes(week: stats.week, labeled: true).frame(height: 120)
                }

                PageSection(label: "models you've used") {
                    ForEach(stats.models, id: \.name) { model in
                        HStack {
                            Text(model.name.lowercased()).font(.ui(16)).foregroundStyle(theme.text)
                            Spacer()
                            Text("\(model.count) \(model.count == 1 ? "note" : "notes") · \(model.words.formatted()) words")
                                .font(.mono(13)).foregroundStyle(theme.sub)
                        }
                    }
                }

                Text("Time saved compares your words to typing them on a phone, about \(Int(Stats.phoneTypingWPM)) words a minute on average (Palin et al., 2019, a study of 37,000 people), minus the time you spent talking.")
                    .font(.ui(13)).foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ value: String, _ label: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.mono(26, .semibold)).foregroundStyle(color ?? theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.mono(12)).foregroundStyle(theme.sub)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ tier: ScoreTier) -> Color {
        switch tier {
        case .high: theme.main
        case .moderate: theme.text
        case .low: theme.error
        }
    }
}

/// Words per day for the last week: simple rounded bars, today in the accent color.
struct WeekStrokes: View {
    let week: [(day: Date, words: Int)]
    var labeled = false        // counts above the bars (stats page)
    @Environment(\.theme) private var theme

    var body: some View {
        let most = max(1, week.map(\.words).max() ?? 1)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, entry in
                let today = Calendar.current.isDateInToday(entry.day)
                VStack(spacing: 6) {
                    if labeled {
                        Text(entry.words > 0 ? "\(entry.words)" : "")
                            .font(.mono(10)).foregroundStyle(theme.sub)
                    }
                    GeometryReader { geo in
                        let width: CGFloat = labeled ? 14 : 10
                        // an empty day is a short stub, so every day still has a place
                        let h = entry.words > 0 ? max(width, geo.size.height * CGFloat(entry.words) / CGFloat(most)) : 4
                        Capsule()
                            .fill(entry.words > 0 ? theme.main.opacity(today ? 1 : 0.75) : theme.sub.opacity(0.3))
                            .frame(width: width, height: h)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)).lowercased())
                        .font(.mono(labeled ? 11 : 10))
                        .foregroundStyle(today ? theme.main : theme.sub)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))): \(entry.words) words")
            }
        }
    }
}
