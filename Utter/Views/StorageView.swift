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
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                figure(formatMB(appSizeMB), "the app")
                figure(formatMB(models.totalDiskMB), "speech models")
                figure(formatMB(history.diskMB), "\(history.items.count) notes")
            }
            Text("Speech models take almost all the room. Notes are tiny, even thousands of them, so removing a model you don't use frees far more space than deleting notes.")
                .font(.ui(14)).foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)

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

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.mono(24, .semibold)).foregroundStyle(theme.text)
            Text(caption).font(.mono(12)).foregroundStyle(theme.sub)
        }
    }
}
