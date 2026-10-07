import SwiftUI

/// The writing models (tidy and titles), as a section of the models page.
struct WritersSection: View {
    var label = "smallest to biggest"
    @Environment(\.theme) private var theme
    @State private var store = WriterStore.shared
    @State private var removing: WriterModel?

    var body: some View {
        PageSection(label: label) {
            ForEach(Writers.all) { model in
                WriterRow(model: model, store: store, onRemove: { removing = model })
            }
            if !Assistant.appleAvailable {
                Text("Apple Intelligence isn't on for this iPhone. \(Assistant.unavailableReasonForApple)")
                    .font(.ui(14)).foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { store.refresh() }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove download", role: .destructive) {
                if let model = removing { Task { await store.remove(model) } }
            }
        } message: {
            Text("Frees about \(formatMB(store.diskMB[removing?.id ?? ""] ?? 0)). Your notes stay.")
        }
    }
}

private struct WriterRow: View {
    let model: WriterModel
    let store: WriterStore
    var onRemove: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let status: WriterStore.Status = model.isBuiltIn ? (Assistant.appleAvailable ? .ready : .notDownloaded) : (store.status[model.id] ?? .notDownloaded)
        let inUse = store.selectedID == model.id && status == .ready
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name).font(.ui(17, weight: .semibold)).foregroundStyle(theme.text)
                    if model.recommended {
                        Text("recommended").font(.mono(11)).foregroundStyle(theme.main)
                            .markerUnderline(true, seed: "recommended-writer", color: theme.main.opacity(0.6))
                    }
                }
                Text(model.maker).font(.ui(14)).foregroundStyle(theme.text.opacity(0.8))
                VStack(alignment: .leading, spacing: 2) {
                    tradeoff("+", model.pro, theme.main)
                    tradeoff("−", model.con, theme.sub)
                }
                .padding(.top, 2)
                HStack(spacing: 14) {
                    Text(sizeText(status)).font(.mono(12)).foregroundStyle(theme.sub)
                    if status == .ready, !model.isBuiltIn {
                        Button("remove", action: onRemove)
                            .font(.mono(12))
                            .foregroundStyle(theme.error.opacity(0.85))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if status == .ready { store.select(model) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(status == .ready ? .isButton : [])
            .accessibilityHint(status == .ready ? (inUse ? "In use" : "Double-tap to use") : "")
            trailing(status, inUse: inUse)
        }
        .padding(.vertical, 6)
    }

    private func tradeoff(_ mark: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark).font(.mono(13, .semibold)).foregroundStyle(color)
            Text(text).font(.ui(14)).foregroundStyle(theme.text.opacity(mark == "+" ? 0.85 : 0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sizeText(_ status: WriterStore.Status) -> String {
        if model.isBuiltIn { return "built in · no download" }
        if status == .ready, let mb = store.diskMB[model.id] { return "\(formatMB(mb)) on this iPhone" }
        return "\(model.sizeLabel) download"
    }

    @ViewBuilder private func trailing(_ status: WriterStore.Status, inUse: Bool) -> some View {
        switch status {
        case .notDownloaded:
            if model.isBuiltIn {
                Text("off").font(.mono(13)).foregroundStyle(theme.sub)
            } else {
                Button { store.download(model) } label: {
                    Text("get").font(.mono(15, .semibold)).padding(.horizontal, 4)
                }
                .buttonStyle(SwipeButtonStyle())
                .accessibilityLabel("Download \(model.name)")
            }
        case .downloading(let fraction):
            Button { store.cancel(model) } label: {
                ZStack {
                    Circle().stroke(theme.sub.opacity(0.4), lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.03, fraction))
                        .stroke(theme.main, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill").font(.ui(9)).foregroundStyle(theme.main)
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloading, \(Int(fraction * 100)) percent. Double-tap to cancel")
        case .ready:
            ZStack {
                if inUse {
                    MarkerDot().fill(theme.main)
                } else {
                    MarkerLoop(seed: model.id, round: true, pad: -3)
                        .stroke(theme.sub, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(width: 24, height: 24)
            .padding(.top, 2)
        }
    }
}
