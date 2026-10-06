import SwiftUI

/// What Utter keeps on the phone, and how to slim it down.
struct StorageView: View {
    @Environment(History.self) private var history
    @Environment(ModelStore.self) private var models
    @Environment(\.theme) private var theme
    @AppStorage("keepDays") private var keepDays = 0
    @State private var pendingKeep: Int?
    @State private var confirmClear = false

    private let keepOptions: [(Int, String)] = [(0, "forever"), (365, "1 year"), (90, "90 days"), (30, "30 days")]

    var body: some View {
        Page(title: "storage", showsDone: false) {
            PageSection(label: "on this iphone · \(formatMB(appSizeMB + models.totalDiskMB + history.diskMB))",
                        note: "Models take almost all the room. Notes are tiny, even thousands of them.") {
                let parts: [(String, Double, Color)] = [
                    ("speech models", models.totalDiskMB, theme.main),
                    ("the app", appSizeMB, theme.sub),
                    ("\(history.items.count) notes", history.diskMB, theme.text),
                ]
                SizeBar(parts: parts.map { ($0.1, $0.2) }).frame(height: 13).padding(.bottom, 2)
                ForEach(parts, id: \.0) { name, mb, color in
                    HStack(spacing: 10) {
                        MarkerDot().fill(color).frame(width: 10, height: 10)
                        Text(name).font(.ui(16)).foregroundStyle(theme.text)
                        Spacer(minLength: 12)
                        Text(formatMB(mb)).font(.mono(14)).foregroundStyle(theme.sub)
                    }
                }
            }

            PageSection(label: "speech models") {
                NavigationLink { ModelsView() } label: { PageRow(title: "Remove or add models", value: formatMB(models.totalDiskMB)) }
            }

            PageSection(label: "keep notes for", note: "Older notes are deleted when Utter opens. Export them first (History → •••) if you want a copy.") {
                MarkerChoice(options: keepOptions, selection: Binding(
                    get: { keepDays },
                    set: { days in
                        if days > 0, history.count(olderThanDays: days) > 0 { pendingKeep = days } else { keepDays = days }
                    }))
            }

            PageSection(label: "clear everything") {
                Button { confirmClear = true } label: {
                    Text("delete all \(history.items.count) notes").font(.ui(17)).foregroundStyle(theme.error)
                }
                .disabled(history.items.isEmpty)
            }
        }
        .confirmationDialog(pendingKeep.map { "Delete \(history.count(olderThanDays: $0)) notes older than \(label($0))?" } ?? "",
                            isPresented: Binding(get: { pendingKeep != nil }, set: { if !$0 { pendingKeep = nil } }),
                            titleVisibility: .visible) {
            Button("Delete and keep \(pendingKeep.map(label) ?? "")", role: .destructive) {
                if let days = pendingKeep { keepDays = days; history.delete(olderThanDays: days) }
                pendingKeep = nil
            }
        } message: { Text("This can't be undone.") }
        .confirmationDialog("Delete all \(history.items.count) notes?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { history.clear() }
        } message: { Text("This can't be undone. Your models, dictionary and settings stay.") }
    }

    private func label(_ days: Int) -> String { keepOptions.first { $0.0 == days }?.1 ?? "\(days) days" }

}

/// One hand-drawn bar split by size. Tiny parts still get a sliver, so they show up.
private struct SizeBar: View {
    let parts: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.reduce(0) { $0 + $1.0 }, 0.001)
            let gap: CGFloat = 3, sliver: CGFloat = 6
            let room = geo.size.width - gap * CGFloat(parts.count - 1)
            // tiny parts get a sliver; the rest of the room is shared by size among the others
            let small = parts.filter { room * $0.0 / total < sliver }
            let bigTotal = max(total - small.reduce(0) { $0 + $1.0 }, 0.001)
            let bigRoom = room - sliver * CGFloat(small.count)
            HStack(spacing: gap) {
                ForEach(parts.indices, id: \.self) { i in
                    let share = room * parts[i].0 / total
                    MarkerSwipe().fill(parts[i].1)
                        .frame(width: share < sliver ? sliver : bigRoom * parts[i].0 / bigTotal)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
    }
}
