import Foundation
import Observation
import UIKit
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// The model that tidies notes and names them. Apple Intelligence is built in; the open models
/// (Qwen, from Alibaba) are optional downloads that run on the phone with Apple's MLX, like
/// the speech models: nothing leaves the iPhone either way.
struct WriterModel: Identifiable, Equatable {
    let id: String
    let name: String
    let maker: String
    /// Hugging Face repo with MLX weights; nil for the built-in Apple model
    let repo: String?
    let megabytes: Double
    let pro: String
    let con: String
    var recommended = false
    /// Qwen3 models think out loud unless asked not to
    var noThinking = false

    var isBuiltIn: Bool { repo == nil }
    var sizeLabel: String { isBuiltIn ? "built in" : formatMB(megabytes) }
}

enum Writers {
    static let appleID = "apple"

    // Smallest to biggest. Picked by running the same messy notes through each candidate; ones that
    // rewrote people's words, added notes of their own, or left long notes untouched didn't make it.
    static let all: [WriterModel] = [
        WriterModel(id: appleID, name: "Apple Intelligence", maker: "Apple", repo: nil, megabytes: 0,
                    pro: "no download; fine for short notes",
                    con: "often leaves long, rambling notes as they are", recommended: true),
        WriterModel(id: "qwen3-1.7b", name: "Qwen3 1.7B", maker: "Alibaba", repo: "mlx-community/Qwen3-1.7B-4bit",
                    megabytes: 984,
                    pro: "quick; turns long ramblings into clean sentences",
                    con: "may drop a filler word you meant to keep", noThinking: true),
        WriterModel(id: "qwen3.5-2b", name: "Qwen3.5 2B", maker: "Alibaba", repo: "mlx-community/Qwen3.5-2B-4bit",
                    megabytes: 1_749,
                    pro: "best on long, messy notes; keeps your words",
                    con: "biggest download; slower to start", noThinking: true),
    ]

    static func model(_ id: String?) -> WriterModel? { all.first { $0.id == id } }
}

@MainActor
@Observable
final class WriterStore {
    enum Status: Equatable { case notDownloaded, downloading(Double), ready }

    static let shared = WriterStore()

    private(set) var status: [String: Status] = [:]
    private(set) var diskMB: [String: Double] = [:]
    var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "writer") }
    }
    var selected: WriterModel { Writers.model(selectedID) ?? Writers.all[0] }
    var totalDiskMB: Double { diskMB.values.reduce(0, +) }

    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {
        selectedID = UserDefaults.standard.string(forKey: "writer") ?? Writers.appleID
        refresh()
    }

    func refresh() {
        for model in Writers.all where !model.isBuiltIn && tasks[model.id] == nil {
            let folder = Self.folder(model)
            let present = FileManager.default.fileExists(atPath: folder.appendingPathComponent(".complete").path)
            status[model.id] = present ? .ready : .notDownloaded
            diskMB[model.id] = present ? Self.sizeMB(of: folder) : nil
        }
        if !selected.isBuiltIn, status[selectedID] != .ready, tasks[selectedID] == nil { selectedID = Writers.appleID }
    }

    func isReady(_ model: WriterModel) -> Bool { model.isBuiltIn || status[model.id] == .ready }

    func select(_ model: WriterModel) {
        guard isReady(model) else { return }
        selectedID = model.id
        Haptics.tap()
    }

    func download(_ model: WriterModel) {
        guard let repo = model.repo, tasks[model.id] == nil else { return }
        status[model.id] = .downloading(0)
        let folder = Self.folder(model)
        tasks[model.id] = Task {
            do {
                try await HubFiles.download(repo: repo, to: folder) { fraction in
                    Task { @MainActor in self.status[model.id] = .downloading(fraction) }
                }
                try Data().write(to: folder.appendingPathComponent(".complete"))
                tasks[model.id] = nil
                refresh()
                select(model)
            } catch {
                tasks[model.id] = nil
                try? FileManager.default.removeItem(at: folder)
                refresh()
            }
        }
    }

    func cancel(_ model: WriterModel) {
        tasks[model.id]?.cancel()
    }

    func remove(_ model: WriterModel) async {
        guard !model.isBuiltIn else { return }
        await WriterEngine.shared.unload()
        try? FileManager.default.removeItem(at: Self.folder(model))
        refresh()
    }

    nonisolated static func folder(_ model: WriterModel) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Writers", isDirectory: true)
        return base.appendingPathComponent(model.id, isDirectory: true)
    }

    nonisolated static func sizeMB(of folder: URL) -> Double {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var bytes = 0
        while let url = files?.nextObject() as? URL {
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return Double(bytes) / 1_000_000
    }
}

/// Downloads a model's files from Hugging Face into a folder we own, so Utter can show its size
/// and remove it like the speech models.
enum HubFiles {
    private struct Entry: Decodable { let type: String; let path: String; let size: Int? }

    static func download(repo: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let list = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main")!
        let (data, _) = try await URLSession.shared.data(from: list)
        let wanted = try JSONDecoder().decode([Entry].self, from: data).filter { entry in
            entry.type == "file" && [".safetensors", ".json", ".jinja", ".txt", ".model"].contains { entry.path.hasSuffix($0) }
                && !entry.path.lowercased().hasPrefix("readme")
        }
        let total = Double(max(wanted.reduce(0) { $0 + ($1.size ?? 0) }, 1))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var done = 0.0
        for entry in wanted {
            try Task.checkCancellation()
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(entry.path)")!
            let base = done
            let delegate = ProgressDelegate { got in progress(min(1, (base + Double(got)) / total)) }
            let (tmp, response) = try await URLSession.shared.download(from: url, delegate: delegate)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let dest = folder.appendingPathComponent(entry.path)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            done += Double(entry.size ?? 0)
            progress(min(1, done / total))
        }
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let onBytes: (Int64) -> Void
        init(_ onBytes: @escaping (Int64) -> Void) { self.onBytes = onBytes }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
            onBytes(totalBytesWritten)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

/// Runs a downloaded open model, one request at a time (a title and a tidy check can arrive
/// together; running both at once loaded the model twice and crashed). Keeps the model loaded
/// while Utter is open, and stops and lets it go when Utter leaves the screen: iOS closes apps
/// that use the graphics chip in the background.
actor WriterEngine {
    static let shared = WriterEngine()

    private var loadedID: String?
    private var container: ModelContainer?
    /// the last request in line; each new one waits for it
    private var tail: Task<Void, Never>?
    private var current: Task<String, Error>?

    func respond(with model: WriterModel, instructions: String, to prompt: String) async throws -> String {
        let previous = tail
        let job = Task { () async throws -> String in
            await previous?.value
            try Task.checkCancellation()
            return try await self.run(model, instructions: instructions, prompt: prompt)
        }
        tail = Task { _ = try? await job.value }
        return try await job.value
    }

    private func run(_ model: WriterModel, instructions: String, prompt: String) async throws -> String {
        guard await UIApplication.shared.applicationState == .active else { throw AssistantError.notNow }
        let container = try await load(model)
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 1_500, temperature: 0),
            additionalContext: model.noThinking ? ["enable_thinking": false] : nil)
        let work = Task { try await session.respond(to: prompt) }
        current = work
        defer { current = nil }
        let reply = try await work.value
        try Task.checkCancellation()
        // in case a model thinks out loud anyway
        return reply.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Utter is leaving the screen: stop what's running, then free the memory once it has stopped.
    func stopAndUnload() {
        current?.cancel()
        let previous = tail
        tail = Task {
            await previous?.value
            self.unload()
        }
    }

    func unload() {
        container = nil
        loadedID = nil
        MLX.Memory.clearCache()
    }

    private func load(_ model: WriterModel) async throws -> ModelContainer {
        if loadedID == model.id, let container { return container }
        unload()
        MLX.Memory.cacheLimit = 32 * 1024 * 1024
        let loaded = try await loadModelContainer(from: WriterStore.folder(model), using: TokenizerLoaderBridge())
        container = loaded
        loadedID = model.id
        return loaded
    }
}

// MARK: - Tokenizer bridge
// What mlx-swift-lm's #huggingFaceTokenizerLoader macro generates, written out by hand so the
// project builds without approving a macro: swift-transformers' tokenizers, in MLX's protocol.

private struct TokenizerLoaderBridge: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
