import AVFAudio
import Foundation
import Observation
import OSLog

/// Manages continuous ambient audio capture, streaming to the backend,
/// and routing action plans to the proactive executor.
///
/// Audio capture uses `AVAudioEngine` with on-device Voice Activity Detection
/// (VAD) to filter silence. Only speech segments are streamed to the ambient
/// server via WebSocket. Received action plans are routed to `ProactiveExecutor`
/// for immediate execution (high confidence) or stored as suggestions.
///
/// Priority: TalkMode > VoiceWake > AmbientListening (lowest priority for mic).
@MainActor
@Observable
final class AmbientListeningManager: NSObject {
    var isEnabled: Bool = false
    var isListening: Bool = false
    var isPaused: Bool = false
    var isConnected: Bool = false
    var statusText: String = "Off"
    var lastTranscript: String = ""
    var pendingActionCount: Int = 0

    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "AmbientListening")

    private let audioEngine = AVAudioEngine()
    private var inputTapInstalled = false
    private let wsClient = AmbientWebSocketClient()
    private var proactiveExecutor: ProactiveExecutor?
    private var ambientStore: AmbientStore?
    private var autoConfirmTask: Task<Void, Never>?

    // VAD (Voice Activity Detection)
    private var noiseFloorSamples: [Double] = []
    private var noiseFloor: Double?
    private var noiseFloorReady = false
    private let vadThresholdOffset: Double = 0.12
    private var lastSpeechDetectedAt: Date?
    private let silenceTimeout: TimeInterval = 2.0

    // Server configuration
    private var serverURL: URL?

    override init() {
        super.init()
        self.setupWSCallbacks()
    }

    // MARK: - Configuration

    func configure(
        proactiveExecutor: ProactiveExecutor,
        ambientStore: AmbientStore,
        serverURL: URL?)
    {
        self.proactiveExecutor = proactiveExecutor
        self.ambientStore = ambientStore
        self.serverURL = serverURL
    }

    // MARK: - Enable / Disable

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        if enabled {
            self.logger.info("Ambient listening enabled")
            Task { await self.start() }
        } else {
            self.logger.info("Ambient listening disabled")
            self.stop()
        }
    }

    // MARK: - Start / Stop

    func start() async {
        guard self.isEnabled, !self.isListening else { return }

        self.statusText = "Requesting permissions…"

        let micOk = await Self.requestMicrophonePermission()
        guard micOk else {
            self.statusText = "Microphone permission required"
            return
        }

        guard let serverURL else {
            self.statusText = "No server configured"
            return
        }

        do {
            try Self.configureAudioSession()
            try self.startAudioCapture()
            self.wsClient.connect(to: serverURL)
            self.isListening = true
            self.isPaused = false
            self.statusText = "Listening"
            self.startAutoConfirmLoop()
            self.logger.info("Ambient listening started")
        } catch {
            self.isListening = false
            self.statusText = "Start failed: \(error.localizedDescription)"
            self.logger.error("Start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        self.isEnabled = false
        self.isListening = false
        self.isPaused = false
        self.statusText = "Off"
        self.stopAudioCapture()
        self.wsClient.disconnect()
        self.autoConfirmTask?.cancel()
        self.autoConfirmTask = nil
        self.noiseFloorSamples.removeAll()
        self.noiseFloor = nil
        self.noiseFloorReady = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            self.logger.warning("Audio session deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pause / Resume

    func pause() {
        guard self.isListening else { return }
        self.isPaused = true
        self.statusText = "Paused"
        self.stopAudioCapture()
        self.wsClient.sendPause()
        self.logger.info("Ambient listening paused")
    }

    func resume() async {
        guard self.isEnabled, self.isPaused else { return }
        self.isPaused = false
        do {
            try Self.configureAudioSession()
            try self.startAudioCapture()
            self.wsClient.sendResume()
            self.statusText = "Listening"
            self.logger.info("Ambient listening resumed")
        } catch {
            self.statusText = "Resume failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Background handling

    /// Suspend for background (release mic).
    func suspendForBackground() -> Bool {
        guard self.isEnabled, self.isListening else { return false }
        self.stopAudioCapture()
        self.statusText = "Paused (background)"
        return true
    }

    /// Resume after returning from background.
    func resumeAfterBackground(wasSuspended: Bool) async {
        guard wasSuspended, self.isEnabled else { return }
        await self.start()
    }

    /// Suspend when TalkMode or VoiceWake needs the mic.
    func suspendForHigherPriority() -> Bool {
        guard self.isEnabled, self.isListening else { return false }
        self.stopAudioCapture()
        self.isPaused = true
        self.statusText = "Paused (voice active)"
        return true
    }

    func resumeAfterHigherPriority(wasSuspended: Bool) async {
        guard wasSuspended, self.isEnabled else { return }
        self.isPaused = false
        do {
            try Self.configureAudioSession()
            try self.startAudioCapture()
            self.statusText = "Listening"
        } catch {
            self.statusText = "Resume failed"
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() throws {
        self.stopAudioCapture()

        let input = self.audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "AmbientListening", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid audio input format",
            ])
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.processAudioBuffer(buffer)
            }
        }
        self.inputTapInstalled = true

        self.audioEngine.prepare()
        try self.audioEngine.start()
    }

    private func stopAudioCapture() {
        if self.inputTapInstalled {
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.inputTapInstalled = false
        }
        self.audioEngine.stop()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !self.isPaused else { return }

        // Calculate RMS for VAD
        guard let data = buffer.floatChannelData?.pointee else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameCount {
            let v = data[i]
            sum += v * v
        }
        let rms = Double(sqrt(sum / Float(frameCount)))

        // Dynamic noise floor calibration
        if !self.noiseFloorReady {
            self.noiseFloorSamples.append(rms)
            if self.noiseFloorSamples.count >= 20 {
                let sorted = self.noiseFloorSamples.sorted()
                let take = max(5, sorted.count / 2)
                let avg = sorted.prefix(take).reduce(0.0, +) / Double(take)
                self.noiseFloor = avg
                self.noiseFloorReady = true
                self.noiseFloorSamples.removeAll(keepingCapacity: true)
            }
        }

        // VAD: only stream audio with detected speech
        let threshold: Double
        if let floor = self.noiseFloor, self.noiseFloorReady {
            threshold = min(0.35, max(0.08, floor + self.vadThresholdOffset))
        } else {
            threshold = 0.15
        }

        if rms >= threshold {
            self.lastSpeechDetectedAt = Date()
            // Convert to 16kHz mono int16 PCM and send
            let pcmData = self.convertToPCM16(buffer: buffer)
            if let pcmData {
                self.wsClient.sendAudioChunk(pcmData)
            }
        } else if let lastSpeech = self.lastSpeechDetectedAt,
                  Date().timeIntervalSince(lastSpeech) < self.silenceTimeout
        {
            // Continue sending for a short window after speech ends
            let pcmData = self.convertToPCM16(buffer: buffer)
            if let pcmData {
                self.wsClient.sendAudioChunk(pcmData)
            }
        }
    }

    private func convertToPCM16(buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData?.pointee else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        // Simple downsampling to 16kHz if needed
        let sourceSampleRate = buffer.format.sampleRate
        let targetSampleRate = 16000.0
        let ratio = sourceSampleRate / targetSampleRate
        let outputFrames = Int(Double(frameCount) / ratio)

        var pcmData = Data(count: outputFrames * 2) // 16-bit = 2 bytes
        pcmData.withUnsafeMutableBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<outputFrames {
                let sourceIndex = min(Int(Double(i) * ratio), frameCount - 1)
                let sample = floatData[sourceIndex]
                let clamped = max(-1.0, min(1.0, sample))
                int16Ptr[i] = Int16(clamped * 32767.0)
            }
        }
        return pcmData
    }

    // MARK: - WebSocket Callbacks

    private func setupWSCallbacks() {
        self.wsClient.onTranscript = { [weak self] text, isPartial in
            guard let self else { return }
            if !isPartial {
                self.lastTranscript = text
            }
        }

        self.wsClient.onActionPlan = { [weak self] item in
            guard let self else { return }
            Task {
                await self.proactiveExecutor?.processActionPlan(item)
                self.pendingActionCount = self.ambientStore?.pendingCount ?? 0
            }
        }

        self.wsClient.onConnectionStateChanged = { [weak self] connected in
            guard let self else { return }
            self.isConnected = connected
            if connected {
                self.statusText = self.isPaused ? "Paused" : "Listening"
            } else if self.isEnabled {
                self.statusText = "Reconnecting…"
            }
        }

        self.wsClient.onError = { [weak self] message in
            guard let self else { return }
            self.logger.error("Server error: \(message, privacy: .public)")
        }
    }

    // MARK: - Auto-confirm loop

    private func startAutoConfirmLoop() {
        self.autoConfirmTask?.cancel()
        self.autoConfirmTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Every 60s
                guard let self else { return }
                self.proactiveExecutor?.autoConfirmExpired()
                self.pendingActionCount = self.ambientStore?.pendingCount ?? 0
            }
        }
    }

    // MARK: - Permissions & Audio Session

    static func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [
            .mixWithOthers,
            .allowBluetoothHFP,
            .defaultToSpeaker,
        ])
        try session.setActive(true, options: [])
    }

    nonisolated static func requestMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            }
        @unknown default:
            return false
        }
    }
}
