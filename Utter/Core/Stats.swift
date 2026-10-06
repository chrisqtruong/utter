import Foundation

/// Numbers for the stats page, worked out from history.
struct Stats {
    let dictations: Int
    let words: Int
    let secondsSpoken: Double
    let averageScore: Int
    let streakDays: Int
    let week: [(day: Date, words: Int)]   // the last 7 days, oldest first
    let firstDate: Date?
    let models: [(name: String, count: Int, words: Int)]

    /// Typing on a phone averages about 36 words a minute
    /// (Palin et al., "How do people type on mobile devices?", MobileHCI 2019, 37,000 volunteers).
    static let phoneTypingWPM = 36.0

    var minutesSaved: Double {
        max(0, Double(words) / Self.phoneTypingWPM - secondsSpoken / 60)
    }

    var speakingWPM: Int {
        secondsSpoken > 0 ? Int((Double(words) / (secondsSpoken / 60)).rounded()) : 0
    }

    init(_ items: [Dictation], now: Date = .now) {
        let cal = Calendar.current
        dictations = items.count
        words = items.reduce(0) { $0 + $1.transcript.words.count }
        secondsSpoken = items.reduce(0) { $0 + $1.seconds }
        averageScore = items.isEmpty ? 0 : items.reduce(0) { $0 + $1.transcript.score } / items.count
        firstDate = items.last?.date

        var perDay: [Date: Int] = [:]
        for item in items { perDay[cal.startOfDay(for: item.date), default: 0] += item.transcript.words.count }

        let today = cal.startOfDay(for: now)
        week = (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            return (day, perDay[day] ?? 0)
        }

        // Days in a row with at least one dictation, counting back from today (or yesterday, if today is still empty).
        var streak = 0
        var day = perDay[today] != nil ? today : cal.date(byAdding: .day, value: -1, to: today)!
        while perDay[day] != nil {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        streakDays = streak

        var byModel: [String: (count: Int, words: Int)] = [:]
        for item in items {
            byModel[item.modelName, default: (0, 0)].count += 1
            byModel[item.modelName, default: (0, 0)].words += item.transcript.words.count
        }
        models = byModel.sorted { $0.value.count > $1.value.count }.map { ($0.key, $0.value.count, $0.value.words) }
    }
}

func formatMinutes(_ minutes: Double) -> String {
    if minutes < 1 { return "\(Int((minutes * 60).rounded()))s" }
    if minutes < 60 { return "\(Int(minutes.rounded()))m" }
    let h = Int(minutes / 60), m = Int(minutes.truncatingRemainder(dividingBy: 60))
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}
