import ReplayKit
import AVFoundation

/// Utter's screen-recording add-on. iOS hands it the phone's sound while screen recording is on;
/// it keeps only that sound (never the picture or the mic), shrinks it to 16 kHz mono, and writes it
/// to a shared folder. Utter turns it into text the next time it opens, then deletes the file.
/// Add-ons like this get very little memory, far too little for a speech model, so nothing is transcribed here.
final class SampleHandler: RPBroadcastSampleHandler {
    private let group = "group.com.christruong.utter"
    private let maxSeconds = 60.0 * 60
    private var file: FileHandle?
    private var partURL: URL?
    private var written = 0
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Capture", isDirectory: true) else {
            finishBroadcastWithError(NSError(domain: "Utter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Utter couldn't open its shared folder."]))
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("\(name).part")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        partURL = url
        file = try? FileHandle(forWritingTo: url)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .audioApp, let file, Double(written) < maxSeconds * 16_000 else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }

        if inputFormat != pcm.format {
            inputFormat = pcm.format
            converter = AVAudioConverter(from: pcm.format, to: outFormat)
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * 16_000 / pcm.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return pcm
        }
        guard let data = out.floatChannelData?[0], out.frameLength > 0 else { return }
        file.write(Data(bytes: data, count: Int(out.frameLength) * MemoryLayout<Float>.size))
        written += Int(out.frameLength)
    }

    override func broadcastFinished() {
        try? file?.close()
        file = nil
        guard let partURL else { return }
        // ".f32" means finished: Utter picks it up next time it opens.
        try? FileManager.default.moveItem(at: partURL, to: partURL.deletingPathExtension().appendingPathExtension("f32"))
    }

    /// Copies the sound out of a ReplayKit sample buffer as mono floats at its own sample rate.
    /// ReplayKit often sends 16-bit big-endian stereo, which AVAudioFormat won't take directly,
    /// so the samples are decoded by hand (16/32-bit integer or float, either byte order).
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        let asbd = asbdPointer.pointee
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, asbd.mFormatID == kAudioFormatLinearPCM, asbd.mSampleRate > 0 else { return nil }

        let channels = Int(max(1, asbd.mChannelsPerFrame))
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bigEndian = asbd.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        guard [2, 4].contains(bytesPerSample) else { return nil }

        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes) == noErr else { return nil }

        func sample(at index: Int) -> Float {
            let o = index * bytesPerSample
            guard o + bytesPerSample <= bytes.count else { return 0 }
            if bytesPerSample == 2 {
                var v = UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8
                if bigEndian { v = v.byteSwapped }
                return Float(Int16(bitPattern: v)) / 32_768
            }
            var v = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
            if bigEndian { v = v.byteSwapped }
            return isFloat ? Float(bitPattern: v) : Float(Int32(bitPattern: v)) / 2_147_483_648
        }

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
                sum += sample(at: interleaved ? f * channels + c : c * frames + f)
            }
            out[f] = sum / Float(channels)   // mix down to mono
        }
        return buffer
    }
}
