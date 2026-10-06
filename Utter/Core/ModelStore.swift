import Foundation
import Observation
import FluidAudio
import WhisperKit

/// Downloads, removes and picks speech models, and keeps the chosen one loaded.
@MainActor
@Observable
final class ModelStore {
    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)   // 0–1
        case preparing             // first load after download (compiles for this iPhone)
        case ready
    }

    private(set) var status: [String: Status] = [:]
    private(set) var diskMB: [String: Double] = [:]
    private(set) var isLoading = false
    /// True while loading for the first time since an update: iOS prepares the model for this
    /// iPhone's AI chip once (about a minute), then loads it in a blink every time after.
    private(set) var isFirstSetup = false
    /// True when this model has never been loaded on this iPhone before (not just updated).
    private(set) var isFirstEver = false
    /// When the current load began, for the loading bar's clock.
    private(set) var loadStarted: Date?
    private(set) var loadError: String?

    var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedModel") }
    }

    var selected: SpeechModel? { Catalog.model(selectedID) }
    var selectedIsReady: Bool { selectedID.map { status[$0] == .ready } ?? false }
    var hasAnyModel: Bool { status.values.contains(.ready) }
    var totalDiskMB: Double { diskMB.values.reduce(0, +) }

    let engine = SpeechEngine()
    private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        selectedID = UserDefaults.standard.string(forKey: "selectedModel")
        refresh()
    }

    /// Re-checks which models are on disk and how much room they take.
    func refresh() {
        for model in Catalog.models where tasks[model.id] == nil {
            let folder = Self.folder(model)
            let present: Bool = switch model.family {
            case .whisper: FileManager.default.fileExists(atPath: folder.appendingPathComponent("AudioEncoder.mlmodelc").path)
            case .parakeet: AsrModels.modelsExist(at: folder, version: model.parakeetVersion)
            }
            status[model.id] = present ? .ready : .notDownloaded
            diskMB[model.id] = present ? Self.sizeMB(of: folder) : nil
        }
        if let id = selectedID, status[id] != .ready, tasks[id] == nil {
            selectedID = Catalog.models.first { status[$0.id] == .ready }?.id
        }
    }

    // MARK: Download / remove

    func download(_ model: SpeechModel) {
        guard tasks[model.id] == nil else { return }
        status[model.id] = .downloading(0)
        tasks[model.id] = Task {
            do {
                switch model.family {
                case .whisper:
                    _ = try await WhisperKit.download(variant: model.whisperVariant, downloadBase: SpeechEngine.whisperBase) { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in self.status[model.id] = .downloading(fraction) }
                    }
                case .parakeet:
                    try await AsrModels.download(version: model.parakeetVersion) { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in self.status[model.id] = .downloading(fraction) }
                    }
                }
                try Task.checkCancellation()
                // Load once now: Whisper fetches its small word list, and Core ML
                // tunes the model for this iPhone, so the first dictation is quick.
                status[model.id] = .preparing
                try await engine.load(model)
                tasks[model.id] = nil
                if selected == nil || !selectedIsReady { selectedID = model.id }
                refresh()
                status[model.id] = .ready
            } catch {
                tasks[model.id] = nil
                try? FileManager.default.removeItem(at: Self.folder(model))
                refresh()
                if !(error is CancellationError) { loadError = "Couldn't download \(model.name). Check your connection and try again." }
            }
        }
    }

    func cancel(_ model: SpeechModel) {
        tasks[model.id]?.cancel()
    }

    func remove(_ model: SpeechModel) async {
        if await engine.loadedID == model.id { await engine.unload() }
        try? FileManager.default.removeItem(at: Self.folder(model))
        refresh()
    }

    func select(_ model: SpeechModel) {
        guard status[model.id] == .ready else { return }
        selectedID = model.id
        Task { await loadSelected() }
    }

    func clearError() { loadError = nil }

    // MARK: Loading

    /// Loads the chosen model into memory if it isn't already.
    func loadSelected() async {
        guard let model = selected, status[model.id] == .ready else { return }
        if await engine.loadedID == model.id { return }
        let key = "preparedFor-\(model.id)"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let stamp = "\(build)-\(Bundle.main.bundleURL.path)"   // changes with every install or update
        isFirstSetup = UserDefaults.standard.string(forKey: key) != stamp
        isFirstEver = UserDefaults.standard.string(forKey: key) == nil
        isLoading = true
        loadStarted = Date()
        defer { isLoading = false; isFirstSetup = false; loadStarted = nil }
        do {
            try await engine.load(model)
            UserDefaults.standard.set(stamp, forKey: key)
        } catch {
            loadError = "\(model.name) wouldn't load. Try removing and downloading it again."
        }
    }

    // MARK: Disk

    static func folder(_ model: SpeechModel) -> URL {
        switch model.family {
        case .whisper: SpeechEngine.whisperFolder(model)
        case .parakeet: SpeechEngine.parakeetFolder(model)
        }
    }

    nonisolated static func sizeMB(of folder: URL) -> Double {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var bytes = 0
        for case let url as URL in files {
            bytes += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return Double(bytes) / 1_000_000
    }

    static var freeSpaceMB: Double {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let bytes = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
        return Double(bytes) / 1_000_000
    }
}
