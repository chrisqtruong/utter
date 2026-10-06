import AVFoundation

/// Reads the sound from an audio or video file as 16 kHz mono, the format the speech models want.
enum AudioImport {
    /// Longest file Utter takes in one go: an hour of audio is about 230 MB in memory.
    static let maxSeconds = 60.0 * 60

    struct Loaded {
        var samples: [Float]
        var seconds: Double
        var trimmed: Bool   // longer than an hour; only the first hour was read
    }

    static func load(_ url: URL) async throws -> Loaded {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ImportError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ImportError.unreadable }

        let limit = Int(maxSeconds * 16_000)
        var samples: [Float] = []
        var trimmed = false
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var chunk = [Float](repeating: 0, count: count)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: raw.baseAddress!)
            }
            samples += chunk
            if samples.count >= limit {
                samples.removeLast(samples.count - limit)
                trimmed = true
                reader.cancelReading()
                break
            }
        }
        if reader.status == .failed { throw reader.error ?? ImportError.unreadable }
        guard !samples.isEmpty else { throw ImportError.noAudio }
        return Loaded(samples: samples, seconds: Double(samples.count) / 16_000, trimmed: trimmed)
    }

    /// Reads raw 16 kHz mono float samples, as the screen-recording add-on writes them.
    static func loadRaw(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    enum ImportError: LocalizedError {
        case noAudio, unreadable
        var errorDescription: String? {
            switch self {
            case .noAudio: "That file doesn't have any sound in it."
            case .unreadable: "Couldn't read that file."
            }
        }
    }
}

/// Where the screen-recording add-on leaves what it heard, for the app to pick up.
/// Shared between the app and the add-on through an App Group.
enum CaptureInbox {
    static let group = "group.com.christruong.utter"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Capture", isDirectory: true)
    }

    /// Finished captures waiting to be turned into text, oldest first.
    static func waiting() -> [URL] {
        // a capture that ended badly leaves a ".part" file; keep what it heard
        if let folder, !isCapturing,
           let parts = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for part in parts where part.pathExtension == "part" {
                try? FileManager.default.moveItem(at: part, to: part.deletingPathExtension().appendingPathExtension("f32"))
            }
        }
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
        else { return [] }
        return files.filter { $0.pathExtension == "f32" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// True while the add-on is still capturing (it writes to a ".part" file until it's done).
    static var isCapturing: Bool {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return false }
        // a ".part" file that stopped growing a while ago is left over from a capture that ended badly
        return files.contains { url in
            guard url.pathExtension == "part",
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return false }
            return Date().timeIntervalSince(modified) < 20
        }
    }
}

/// Was anyone actually talking? Checked before waking the speech model,
/// so an accidental tap or a silent clip comes back instantly.
enum SpeechCheck {
    /// True if at least a quarter second of the clip is clearly louder than the room.
    static func hasSpeech(_ samples: [Float]) -> Bool {
        let frame = 480   // 30 ms at 16 kHz
        guard samples.count >= frame * 10 else { return false }
        var levels: [Float] = []
        levels.reserveCapacity(samples.count / frame)
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for s in samples[i..<(i + frame)] { sum += s * s }
            levels.append((sum / Float(frame)).squareRoot())
            i += frame
        }
        let room = levels.sorted()[levels.count / 5]          // quietest fifth: the room
        let threshold = max(0.012, room * 3.5)                 // speech is well above it
        let loudFrames = levels.filter { $0 > threshold }.count
        return loudFrames >= 8                                  // 8 × 30 ms ≈ a quarter second
    }
}
