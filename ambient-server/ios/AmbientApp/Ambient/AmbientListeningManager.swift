import AVFAudio
import Foundation
import Observation
import OSLog

/// Manages continuous ambient audio capture, streaming to the backend,
/// and routing action plans to the proactive executor.
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

    private let logger = Logger(subsystem: "ambient", category: "Listening")
    private let audioEngine = AVAudioEngine()
    private var inputTapInstalled = false
    let wsClient = AmbientWebSocketClient()
    var proactiveExecutor: ProactiveExecutor?
    var ambientStore: AmbientStore?
    private var autoConfirmTask: Task<Void, Never>?
    private var serverURL: URL?

    override init() { super.init(); self.setupWSCallbacks() }

    func configure(executor: ProactiveExecutor, store: AmbientStore, serverURL: URL?) {
        self.proactiveExecutor = executor; self.ambientStore = store; self.serverURL = serverURL
    }

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        if enabled { Task { await self.start() } } else { self.stop() }
    }

    func start() async {
        guard self.isEnabled, !self.isListening else { return }
        self.statusText = "Requesting permissions…"
        let micOk = await Self.requestMicPermission()
        guard micOk else { self.statusText = "Microphone permission required"; return }
        guard let serverURL else { self.statusText = "No server configured"; return }
        do {
            try Self.configureAudioSession()
            try self.startAudioCapture()
            self.wsClient.connect(to: serverURL)
            self.isListening = true; self.isPaused = false; self.statusText = "Listening"
            self.startAutoConfirmLoop()
        } catch {
            self.isListening = false; self.statusText = "Start failed: \(error.localizedDescription)"
        }
    }

    func stop() {
        self.isEnabled = false; self.isListening = false; self.isPaused = false; self.statusText = "Off"
        self.stopAudioCapture(); self.wsClient.disconnect()
        self.autoConfirmTask?.cancel(); self.autoConfirmTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func pause() {
        guard self.isListening else { return }
        self.isPaused = true; self.statusText = "Paused"
        self.stopAudioCapture(); self.wsClient.sendPause()
    }

    func resume() async {
        guard self.isEnabled, self.isPaused else { return }
        self.isPaused = false
        do {
            try Self.configureAudioSession(); try self.startAudioCapture()
            self.wsClient.sendResume(); self.statusText = "Listening"
        } catch { self.statusText = "Resume failed" }
    }

    func suspendForBackground() -> Bool {
        guard self.isEnabled, self.isListening else { return false }
        self.stopAudioCapture(); self.statusText = "Paused (background)"; return true
    }

    func resumeAfterBackground(wasSuspended: Bool) async {
        guard wasSuspended, self.isEnabled else { return }; await self.start()
    }

    // MARK: - Audio Capture

    private func startAudioCapture() throws {
        self.stopAudioCapture()
        let input = self.audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Ambient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }
        input.removeTap(onBus: 0)
        let client = self.wsClient
        let vadState = VADState()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            Self.processAudio(buffer: buffer, vadState: vadState, send: { client.sendAudioChunk($0) })
        }
        self.inputTapInstalled = true
        self.audioEngine.prepare(); try self.audioEngine.start()
    }

    private func stopAudioCapture() {
        if self.inputTapInstalled { self.audioEngine.inputNode.removeTap(onBus: 0); self.inputTapInstalled = false }
        self.audioEngine.stop()
    }

    /// Runs on audio thread — no MainActor.
    private nonisolated static func processAudio(buffer: AVAudioPCMBuffer, vadState: VADState, send: @Sendable (Data) -> Void) {
        guard let data = buffer.floatChannelData?.pointee else { return }
        let n = Int(buffer.frameLength); guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { let v = data[i]; sum += v * v }
        let rms = Double(sqrt(sum / Float(n)))

        vadState.lock.lock()
        if !vadState.ready {
            vadState.samples.append(rms)
            if vadState.samples.count >= 20 {
                let sorted = vadState.samples.sorted()
                vadState.floor = sorted.prefix(max(5, sorted.count / 2)).reduce(0, +) / Double(max(5, sorted.count / 2))
                vadState.ready = true; vadState.samples.removeAll()
            }
        }
        let threshold = vadState.ready ? min(0.35, max(0.08, (vadState.floor ?? 0.1) + 0.12)) : 0.15
        let now = Date()
        let shouldSend = rms >= threshold || (vadState.lastSpeech.map { now.timeIntervalSince($0) < 2.0 } ?? false)
        if rms >= threshold { vadState.lastSpeech = now }
        vadState.lock.unlock()

        guard shouldSend else { return }
        let sr = buffer.format.sampleRate; let ratio = sr / 16000.0
        let outFrames = Int(Double(n) / ratio)
        var pcm = Data(count: outFrames * 2)
        pcm.withUnsafeMutableBytes { ptr in
            let p = ptr.bindMemory(to: Int16.self)
            for i in 0..<outFrames {
                let si = min(Int(Double(i) * ratio), n - 1)
                p[i] = Int16(max(-1, min(1, data[si])) * 32767)
            }
        }
        send(pcm)
    }

    // MARK: - WebSocket Callbacks

    private func setupWSCallbacks() {
        self.wsClient.onTranscript = { [weak self] text, isPartial in
            guard let self else { return }; if !isPartial { self.lastTranscript = text }
        }
        self.wsClient.onActionPlan = { [weak self] item in
            guard let self else { return }
            Task { await self.proactiveExecutor?.processActionPlan(item); self.pendingActionCount = self.ambientStore?.pendingCount ?? 0 }
        }
        self.wsClient.onConnectionStateChanged = { [weak self] connected in
            guard let self else { return }
            self.isConnected = connected
            self.statusText = connected ? (self.isPaused ? "Paused" : "Listening") : (self.isEnabled ? "Reconnecting…" : "Off")
        }
        self.wsClient.onError = { [weak self] msg in self?.logger.error("Server: \(msg, privacy: .public)") }
    }

    private func startAutoConfirmLoop() {
        self.autoConfirmTask?.cancel()
        self.autoConfirmTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.proactiveExecutor?.autoConfirmExpired()
                await MainActor.run { self?.pendingActionCount = self?.ambientStore?.pendingCount ?? 0 }
            }
        }
    }

    static func configureAudioSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try s.setActive(true)
    }

    nonisolated static func requestMicPermission() async -> Bool {
        let s = AVAudioSession.sharedInstance()
        switch s.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }
}

private final class VADState: @unchecked Sendable {
    let lock = NSLock()
    var samples: [Double] = []; var floor: Double?; var ready = false; var lastSpeech: Date?
}
