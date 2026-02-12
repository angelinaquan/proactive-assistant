import AVFAudio
import Speech
import SwiftUI

/// Full-screen AI video chat with avatar and live transcript.
///
/// Complete loop:
/// 1. Captures mic audio via AVAudioEngine
/// 2. Runs on-device speech recognition (SFSpeechRecognizer)
/// 3. On silence, sends finalized transcript to server POST /chat
/// 4. Receives AI response text
/// 5. Speaks response via AVSpeechSynthesizer (system TTS)
/// 6. Animates avatar during speech (isSpeaking drives glow animation)
/// 7. Resumes listening after speech completes
struct VideoChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var engine = VideoChatEngine()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video Chat").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        if self.engine.isListening || self.engine.isSpeaking {
                            HStack(spacing: 4) {
                                Circle().fill(self.engine.isSpeaking ? .purple : .green).frame(width: 6, height: 6)
                                Text(self.engine.isSpeaking ? "Speaking" : "Listening")
                                    .font(.caption2).foregroundStyle(self.engine.isSpeaking ? .purple : .green)
                            }
                        }
                    }
                    Spacer()
                    Button { self.engine.stopAll(); self.dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6))
                    }
                }.padding(.horizontal, 20).padding(.top, 12)

                Spacer()

                // AI Avatar
                AIAvatarView(
                    micLevel: self.engine.micLevel,
                    isSpeaking: self.engine.isSpeaking,
                    isThinking: self.engine.isThinking,
                    isListening: self.engine.isListening,
                    statusText: self.engine.statusText,
                    agentName: "Assistant",
                    avatarImageURL: self.appModel.avatarImageURL,
                    accentColor: .blue)

                Spacer()

                // Transcript area
                VStack(alignment: .leading, spacing: 10) {
                    if !self.engine.userTranscript.isEmpty {
                        TranscriptLine(role: "You", text: self.engine.userTranscript, color: .blue, isActive: self.engine.isListening)
                    }
                    if !self.engine.assistantText.isEmpty {
                        TranscriptLine(role: "AI", text: self.engine.assistantText, color: .purple, isActive: self.engine.isSpeaking)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.8))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 0.5)))
                .padding(.horizontal, 16).padding(.bottom, 16)

                // Controls
                HStack(spacing: 40) {
                    Button {
                        if self.engine.isListening { self.engine.pauseListening() }
                        else { Task { await self.engine.startListening() } }
                    } label: {
                        ZStack {
                            Circle().fill(self.engine.isListening ? .white.opacity(0.15) : .red.opacity(0.8))
                                .frame(width: 52, height: 52)
                            Image(systemName: self.engine.isListening ? "mic.fill" : "mic.slash.fill")
                                .font(.title3).foregroundStyle(.white)
                        }
                    }

                    Button { self.engine.stopAll(); self.dismiss() } label: {
                        ZStack {
                            Circle().fill(.red).frame(width: 64, height: 64)
                            Image(systemName: "phone.down.fill").font(.title2).foregroundStyle(.white)
                        }.shadow(color: .red.opacity(0.4), radius: 12, y: 4)
                    }

                    // Symmetry spacer
                    Circle().fill(.clear).frame(width: 52, height: 52)
                }
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            self.engine.configure(serverBaseURL: self.buildBaseURL())
            Task { await self.engine.startListening() }
        }
        .onDisappear { self.engine.stopAll() }
    }

    private func buildBaseURL() -> URL? {
        let host = UserDefaults.standard.string(forKey: "ambient.serverHost") ?? ""
        let port = UserDefaults.standard.integer(forKey: "ambient.serverPort")
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        let p = port > 0 ? port : 8200
        return URL(string: "http://\(h):\(p)")
    }
}

// MARK: - Transcript line

private struct TranscriptLine: View {
    let role: String; let text: String; let color: Color; let isActive: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if self.isActive { Circle().fill(self.color).frame(width: 6, height: 6) }
                Text(self.role).font(.caption2.weight(.semibold)).foregroundStyle(self.color.opacity(0.8))
            }
            Text(self.text).font(.callout).foregroundStyle(.white.opacity(0.9)).lineLimit(4)
        }
    }
}

// MARK: - VideoChatEngine

/// Complete voice chat engine: mic capture → speech recognition → server chat → TTS → avatar.
@MainActor
@Observable
final class VideoChatEngine: NSObject, AVSpeechSynthesizerDelegate {
    // State
    var isListening = false
    var isSpeaking = false
    var isThinking = false
    var micLevel: Double = 0
    var statusText = "Tap mic to start"
    var userTranscript = ""
    var assistantText = ""

    // Audio
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false

    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsCompletion: CheckedContinuation<Void, Never>?

    // Chat
    private var chatClient: ChatClient?
    private var serverBaseURL: URL?

    // Silence detection for end-of-utterance
    private var lastSpeechTime: Date?
    private var silenceTimer: Task<Void, Never>?
    private let silenceThreshold: TimeInterval = 1.5
    private var hasSentCurrentUtterance = false

    override init() {
        super.init()
        self.synthesizer.delegate = self
    }

    func configure(serverBaseURL: URL?) {
        self.serverBaseURL = serverBaseURL
        self.chatClient = ChatClient()
    }

    // MARK: - Listening

    func startListening() async {
        guard !self.isListening else { return }
        self.statusText = "Requesting permissions…"

        let micOk = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micOk else { self.statusText = "Microphone denied"; return }

        let speechOk = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOk else { self.statusText = "Speech recognition denied"; return }

        self.speechRecognizer = SFSpeechRecognizer()
        guard self.speechRecognizer != nil else { self.statusText = "Recognizer unavailable"; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            try self.startRecognition()
            self.isListening = true
            self.statusText = "Listening"
            self.userTranscript = ""
            self.hasSentCurrentUtterance = false
            self.startSilenceDetection()
        } catch {
            self.statusText = "Start failed: \(error.localizedDescription)"
        }
    }

    func pauseListening() {
        self.isListening = false
        self.statusText = "Paused"
        self.stopRecognition()
        self.silenceTimer?.cancel()
    }

    func stopAll() {
        self.isListening = false
        self.isSpeaking = false
        self.isThinking = false
        self.statusText = "Off"
        self.stopRecognition()
        self.silenceTimer?.cancel()
        self.synthesizer.stopSpeaking(at: .immediate)
        if let c = self.ttsCompletion { self.ttsCompletion = nil; c.resume() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Speech Recognition

    private func startRecognition() throws {
        self.stopRecognition()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let input = self.audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw NSError(domain: "VC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad format"]) }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            if let data = buffer.floatChannelData?.pointee {
                let n = Int(buffer.frameLength)
                if n > 0 {
                    var sum: Float = 0
                    for i in 0..<n { let v = data[i]; sum += v * v }
                    let rms = Double(sqrt(sum / Float(n)))
                    let level = max(0, min(1, rms * 10))
                    Task { @MainActor in self?.micLevel = (self?.micLevel ?? 0) * 0.7 + level * 0.3 }
                }
            }
        }
        self.inputTapInstalled = true
        self.audioEngine.prepare()
        try self.audioEngine.start()

        self.recognitionTask = self.speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.userTranscript = text
                    self.lastSpeechTime = Date()
                    self.hasSentCurrentUtterance = false
                }
                if let error {
                    let msg = error.localizedDescription
                    if !msg.localizedCaseInsensitiveContains("no speech detected") {
                        self.statusText = "Error: \(msg)"
                    }
                    if self.isListening {
                        self.stopRecognition()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if self.isListening { try? self.startRecognition() }
                    }
                }
            }
        }
    }

    private func stopRecognition() {
        self.recognitionTask?.cancel(); self.recognitionTask = nil
        self.recognitionRequest?.endAudio(); self.recognitionRequest = nil
        if self.inputTapInstalled { self.audioEngine.inputNode.removeTap(onBus: 0); self.inputTapInstalled = false }
        self.audioEngine.stop()
        self.speechRecognizer = nil
        self.micLevel = 0
    }

    // MARK: - Silence Detection → Send to Server

    private func startSilenceDetection() {
        self.silenceTimer?.cancel()
        self.silenceTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000) // Check every 300ms
                guard let self else { return }
                guard self.isListening, !self.isSpeaking, !self.isThinking else { continue }

                let transcript = self.userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty, !self.hasSentCurrentUtterance else { continue }

                if let lastSpeech = self.lastSpeechTime,
                   Date().timeIntervalSince(lastSpeech) >= self.silenceThreshold
                {
                    self.hasSentCurrentUtterance = true
                    await self.sendToServerAndSpeak(transcript)
                }
            }
        }
    }

    private func sendToServerAndSpeak(_ userText: String) async {
        guard let serverBaseURL, let chatClient else {
            self.statusText = "No server configured"
            return
        }

        // Stop listening while processing
        self.stopRecognition()
        self.isListening = false
        self.isThinking = true
        self.statusText = "Thinking…"

        do {
            let reply = try await chatClient.send(message: userText, serverBaseURL: serverBaseURL)
            self.assistantText = reply
            self.isThinking = false

            // Speak the response
            await self.speak(reply)

            // Resume listening
            self.assistantText = ""
            self.userTranscript = ""
            try? self.startRecognition()
            self.isListening = true
            self.hasSentCurrentUtterance = false
            self.statusText = "Listening"
            self.startSilenceDetection()
        } catch {
            self.isThinking = false
            self.statusText = "Error: \(error.localizedDescription)"
            // Resume listening after error
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try? self.startRecognition()
            self.isListening = true
            self.hasSentCurrentUtterance = false
            self.statusText = "Listening"
            self.startSilenceDetection()
        }
    }

    // MARK: - TTS

    private func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Configure audio for playback
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])

        self.isSpeaking = true
        self.statusText = "Speaking"

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.ttsCompletion = cont
            self.synthesizer.speak(utterance)
        }

        self.isSpeaking = false

        // Restore audio for recording
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
    }

    // AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let c = self.ttsCompletion { self.ttsCompletion = nil; c.resume() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let c = self.ttsCompletion { self.ttsCompletion = nil; c.resume() }
        }
    }
}
