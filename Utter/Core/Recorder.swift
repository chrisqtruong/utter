import AVFoundation

/// Captures the microphone into memory as 16 kHz mono audio, the format both
/// speech models want. Nothing is written to disk.
final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var peak: Float = 0
    /// False while in standby: the mic stays on (so the app may listen from the background)
    /// but nothing is kept. Used by the keyboard session.
    private var capturing = true

    /// Called on the audio thread with a 0–1 loudness for the waveform.
    var onLevel: ((Float) -> Void)?
    /// Called once when the recording should end on its own: the time limit, or a phone call taking the mic.
    var onMustStop: ((String) -> Void)?

    /// 30 minutes of 16 kHz audio is about 115 MB in memory, which every recent iPhone handles easily.
    static let sampleRate = 16_000.0
    static let maxSeconds = 30.0 * 60
    private var interruption: NSObjectProtocol?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        // iOS mutes haptics and system sounds while recording; keep them on, so the Utter keyboard's
        // taps (and the rest of the phone) still feel normal during a keyboard session
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.channelCount > 0, inFormat.sampleRate > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { throw UtterError.micUnavailable }

        lock.withLock { samples = []; peak = 0; capturing = true }
        let ratio = Self.sampleRate / inFormat.sampleRate
        let maxSamples = Int(Self.maxSeconds * Self.sampleRate)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard let data = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            var sum: Float = 0
            for s in chunk { sum += s * s }
            let rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()
            let (keeping, full) = self.lock.withLock { () -> (Bool, Bool) in
                guard self.capturing else { return (false, false) }
                if self.samples.count < maxSamples { self.samples += chunk }
                self.peak = max(self.peak, rms)
                return (true, self.samples.count >= maxSamples)
            }
            guard keeping else { return }
            if full { self.onMustStop?("Stopped at 30 minutes, the longest one take can be.") }
            // Speech sits around 0.01–0.2 RMS; stretch it so the bars move nicely.
            self.onLevel?(min(1, (rms * 12).squareRoot()))
        }
        engine.prepare()
        try engine.start()

        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self?.onMustStop?("Stopped because something else needed the mic. What you said so far is saved.")
        }
    }

    // MARK: Standby (keyboard session)

    /// Turns the mic on without keeping anything yet.
    func startStandby() throws {
        try start()
        lock.withLock { capturing = false; samples = [] }
    }

    /// Starts keeping audio, with the mic already on.
    func beginCapture() {
        lock.withLock { samples = []; peak = 0; capturing = true }
    }

    /// Hands back what was heard and goes back to standby; the mic stays on.
    func endCapture() -> [Float] {
        lock.withLock {
            let out = samples
            samples = []; capturing = false
            return out
        }
    }

    /// Stops and hands back the audio, plus whether anything louder than room noise was heard.
    func stop() -> (samples: [Float], heardSomething: Bool) {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return lock.withLock {
            let result = (samples, peak > 0.004)
            samples = []
            return result
        }
    }
}
