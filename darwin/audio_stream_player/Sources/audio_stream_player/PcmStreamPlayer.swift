import AVFoundation

/// Streams raw PCM chunks through an `AVAudioPlayerNode`.
///
/// Fed chunks are converted to the node's float32 deinterleaved format and
/// scheduled back-to-back, which `AVAudioPlayerNode` plays gaplessly. The
/// engine's mixer resamples from the stream's rate to the hardware rate.
///
/// All methods must be called on the main thread; buffer completion callbacks
/// and engine notifications hop to the main thread before touching state, so
/// no locking is needed.
///
/// The engine stops itself on a configuration change (a route or hardware
/// sample-rate change, such as connecting AirPods mid-utterance). The player
/// observes that and restarts the engine if it was audibly playing, so it
/// never sits silent while reporting `playing`.
final class PcmStreamPlayer {
    enum PcmError: Error {
        case badConfiguration(String)
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Int
    private let channels: Int
    private let isFloat: Bool
    private let emit: ([String: Any]) -> Void

    private var playing = false
    private var paused = false
    private var eosPending = false
    private var underrunReported = false
    private var framesScheduled: Int64 = 0
    private var framesCompleted: Int64 = 0
    private var buffersPending = 0
    // Bumped on stop/dispose so completions from cleared buffers are ignored.
    private var generation: Int64 = 0
    private var configChangeObserver: NSObjectProtocol?

    /// True when an audio session interruption paused this player, so it may
    /// resume when the interruption ends. Cleared by any explicit control.
    private(set) var pausedByInterruption = false

    /// True when the player is neither playing nor paused.
    var isIdle: Bool { !playing }

    init(
        sampleRate: Int, channels: Int, isFloat: Bool,
        emit: @escaping ([String: Any]) -> Void
    ) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: false)
        else {
            throw PcmError.badConfiguration(
                "Unsupported PCM configuration: \(sampleRate)Hz \(channels)ch")
        }
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
        self.isFloat = isFloat
        self.emit = emit
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    func feed(_ data: Data) throws {
        underrunReported = false
        let buffer = try makeBuffer(data)
        buffersPending += 1
        framesScheduled += Int64(buffer.frameLength)
        let myGeneration = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.bufferPlayedBack(
                    frames: Int64(buffer.frameLength), from: myGeneration)
            }
        }
    }

    func play() throws {
        pausedByInterruption = false
        if playing && !paused { return }
        if !engine.isRunning {
            try engine.start()
        }
        node.play()
        playing = true
        paused = false
        emit(["event": "state", "state": "playing"])
    }

    func pause() {
        // An explicit pause overrides a pending resume after an interruption.
        pausedByInterruption = false
        if !playing || paused { return }
        node.pause()
        paused = true
        emit(["event": "state", "state": "paused"])
    }

    func stop() {
        let wasActive = playing
        reset()
        if wasActive {
            emit(["event": "state", "state": "idle"])
        }
    }

    func endOfStream() {
        eosPending = true
        if buffersPending == 0 {
            drain()
        }
    }

    func setVolume(_ volume: Double) {
        node.volume = Float(volume)
    }

    func bufferedDurationMicros() -> Int64 {
        // Completion-count based: overestimates by the not-yet-finished part
        // of the currently playing chunk, which is fine for a gauge and stays
        // correct across underruns (unlike playerTime, which keeps advancing
        // through starvation silence).
        let frames = max(0, framesScheduled - framesCompleted)
        return frames * 1_000_000 / Int64(sampleRate)
    }

    func release() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        reset()
        engine.stop()
        engine.detach(node)
    }

    /// Stops the engine of an idle player so the audio session can be
    /// deactivated without running I/O. `play()` restarts it. A player with
    /// audio fed ahead of `play()` keeps its engine, so stopping can never
    /// discard that audio. Returns true when the engine is no longer running.
    func stopEngineIfIdle() -> Bool {
        if !playing && buffersPending == 0 && engine.isRunning {
            engine.stop()
        }
        return !engine.isRunning
    }

    /// The system interrupted the audio session (a phone call or Siri) and
    /// stopped the engine. Moves a playing player to paused.
    func interruptionBegan() {
        guard playing && !paused else { return }
        node.pause()
        paused = true
        pausedByInterruption = true
        emit(["event": "state", "state": "paused"])
    }

    /// Resumes a player that an interruption paused. Reports failures as an
    /// error event, since no method call is in flight to return them to.
    func resumeAfterInterruption() {
        guard pausedByInterruption else { return }
        do {
            try play()
        } catch {
            emitError("Could not resume after interruption: \(error)")
        }
    }

    /// Forgets an interruption pause without resuming.
    func clearInterruption() {
        pausedByInterruption = false
    }

    func emitError(_ message: String) {
        emit(["event": "error", "message": message])
    }

    private func handleConfigurationChange() {
        // The engine stopped itself. Idle and paused players restart it in
        // play(); only audible playback needs an immediate restart. The node
        // connection uses the stream format, which a route change does not
        // affect, and the main mixer adapts to the new hardware format.
        guard playing && !paused else { return }
        do {
            try engine.start()
            node.play()
        } catch {
            node.pause()
            paused = true
            emitError("Could not restart audio after a route change: \(error)")
            emit(["event": "state", "state": "paused"])
        }
    }

    private func reset() {
        generation += 1
        node.stop()
        playing = false
        paused = false
        pausedByInterruption = false
        eosPending = false
        underrunReported = false
        framesScheduled = 0
        framesCompleted = 0
        buffersPending = 0
    }

    private func bufferPlayedBack(frames: Int64, from bufferGeneration: Int64) {
        guard bufferGeneration == generation else { return }
        framesCompleted += frames
        buffersPending -= 1
        guard buffersPending == 0 else { return }
        if eosPending {
            drain()
        } else if playing && !paused && !underrunReported {
            underrunReported = true
            emit(["event": "underrun"])
        }
    }

    private func drain() {
        let wasActive = playing
        reset()
        if wasActive {
            emit(["event": "state", "state": "idle"])
        }
        emit(["event": "drained"])
    }

    private func makeBuffer(_ data: Data) throws -> AVAudioPCMBuffer {
        let bytesPerSample = isFloat ? 4 : 2
        let frameCount = data.count / (bytesPerSample * channels)
        guard frameCount > 0,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            throw PcmError.badConfiguration("Could not allocate PCM buffer")
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let dst = buffer.floatChannelData!
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if isFloat {
                let src = raw.bindMemory(to: Float32.self)
                for frame in 0..<frameCount {
                    for ch in 0..<channels {
                        dst[ch][frame] = src[frame * channels + ch]
                    }
                }
            } else {
                let src = raw.bindMemory(to: Int16.self)
                let scale: Float = 1.0 / 32768.0
                for frame in 0..<frameCount {
                    for ch in 0..<channels {
                        dst[ch][frame] =
                            Float(Int16(littleEndian: src[frame * channels + ch])) * scale
                    }
                }
            }
        }
        return buffer
    }
}
