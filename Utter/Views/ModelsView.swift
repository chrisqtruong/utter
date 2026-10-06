import SwiftUI

struct ModelsView: View {
    var inSheet = false
    @Environment(ModelStore.self) private var models
    @Environment(\.theme) private var theme
    @State private var removing: SpeechModel?

    var body: some View {
        Page(title: "models", showsDone: inSheet) {
            Text("Tap a downloaded model to use it. Remove ones you don't need to free up space; you can get them again any time.")
                .font(.ui(15)).foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            PageSection(label: "fast · parakeet") {
                ForEach(Catalog.models.filter { $0.family == .parakeet }) { row($0) }
            }
            PageSection(label: "more languages · whisper") {
                ForEach(Catalog.models.filter { $0.family == .whisper }) { row($0) }
            }
            if let error = models.loadError {
                Text(error).font(.mono(13)).foregroundStyle(theme.error)
                    .onTapGesture { models.clearError() }
            }
            Text("on this iPhone: \(formatMB(models.totalDiskMB)) · free: \(formatMB(ModelStore.freeSpaceMB))")
                .font(.mono(12)).foregroundStyle(theme.sub)
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove download", role: .destructive) {
                if let model = removing { Task { await models.remove(model) } }
            }
        } message: {
            Text("Frees about \(formatMB(models.diskMB[removing?.id ?? ""] ?? 0)). Your history stays.")
        }
    }

    private func row(_ model: SpeechModel) -> some View {
        ModelRow(model: model, onRemove: { removing = model })
            .padding(.vertical, 2)
    }
}

struct ModelRow: View {
    let model: SpeechModel
    var onRemove: (() -> Void)?
    @Environment(ModelStore.self) private var models
    @Environment(VoiceProfile.self) private var voice
    @Environment(\.theme) private var theme

    var body: some View {
        let status = models.status[model.id] ?? .notDownloaded
        let inUse = models.selectedID == model.id && status == .ready
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.name).font(.ui(17, weight: .semibold)).foregroundStyle(theme.text)
                        if model.recommended {
                            Text("recommended").font(.mono(11)).foregroundStyle(theme.main)
                                .markerUnderline(true, seed: "recommended", color: theme.main.opacity(0.6))
                        }
                    }
                    Text(model.languages).font(.ui(14)).foregroundStyle(theme.text.opacity(0.8))
                    VStack(alignment: .leading, spacing: 2) {
                        tradeoff("+", model.pro, theme.main)
                        tradeoff("−", model.con, theme.sub)
                    }
                    .padding(.top, 2)
                    if let mine = voice.result?.models.first(where: { $0.id == model.id }) {
                        Text("\(Int((mine.accuracy * 100).rounded()))% of your words right in your voice check")
                            .font(.mono(11)).foregroundStyle(theme.main)
                    }
                    HStack(spacing: 14) {
                        Text(sizeText(status)).font(.mono(12)).foregroundStyle(theme.sub)
                        if status == .ready, let onRemove {
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
            // Tapping a downloaded model picks it. (The get/cancel button on the right is separate.)
            .onTapGesture { if status == .ready { models.select(model) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(status == .ready ? .isButton : [])
            .accessibilityHint(status == .ready ? (inUse ? "In use" : "Double-tap to use") : "")
            trailing(status, inUse: inUse)
        }
        .padding(.vertical, 4)
    }

    private func tradeoff(_ mark: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark).font(.mono(13, .semibold)).foregroundStyle(color)
            Text(text).font(.ui(14)).foregroundStyle(theme.text.opacity(mark == "+" ? 0.85 : 0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sizeText(_ status: ModelStore.Status) -> String {
        if status == .ready, let mb = models.diskMB[model.id] { return "\(formatMB(mb)) on this iPhone" }
        return "\(model.sizeLabel) download"
    }

    @ViewBuilder private func trailing(_ status: ModelStore.Status, inUse: Bool) -> some View {
        switch status {
        case .notDownloaded:
            Button { models.download(model) } label: {
                Text("get").font(.mono(15, .semibold)).padding(.horizontal, 4)
            }
            .buttonStyle(SwipeButtonStyle())
            .accessibilityLabel("Download \(model.name)")
        case .downloading(let fraction):
            Button { models.cancel(model) } label: {
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
        case .preparing:
            VStack(spacing: 4) {
                MarkerSpinner()
                Text("setting up").font(.mono(10)).foregroundStyle(theme.sub)
            }
        case .ready:
            // in use: a marker dot. downloaded but not in use: an empty hand-drawn ring.
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
