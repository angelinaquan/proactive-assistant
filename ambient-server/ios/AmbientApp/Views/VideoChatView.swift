import AVFAudio
import Speech
import SwiftUI

/// Full-screen AI video chat with avatar and live transcript.
/// Captures audio via AVAudioEngine, runs on-device speech recognition,
/// and sends transcripts to the ambient server for AI responses.
struct VideoChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var voiceEngine = VideoChatVoiceEngine()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video Chat").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        if self.voiceEngine.isListening {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("Active").font(.caption2).foregroundStyle(.green)
                            }
                        }
                    }
                    Spacer()
                    Button { self.dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6))
                    }
                }.padding(.horizontal, 20).padding(.top, 12)

                Spacer()

                AIAvatarView(
                    micLevel: self.voiceEngine.micLevel,
                    isSpeaking: false,
                    isThinking: false,
                    isListening: self.voiceEngine.isListening,
                    statusText: self.voiceEngine.statusText,
                    agentName: "Assistant",
                    avatarImageURL: self.appModel.avatarImageURL,
                    accentColor: .blue)

                Spacer()

                // Live transcript
                if !self.voiceEngine.currentTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Circle().fill(.blue).frame(width: 6, height: 6)
                            Text("You").font(.caption2.weight(.semibold)).foregroundStyle(.blue.opacity(0.8))
                        }
                        Text(self.voiceEngine.currentTranscript)
                            .font(.callout).foregroundStyle(.white.opacity(0.9)).lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.8))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 0.5)))
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }

                // Controls
                HStack(spacing: 40) {
                    // Mute toggle
                    Button {
                        if self.voiceEngine.isListening { self.voiceEngine.stopListening() }
                        else { Task { await self.voiceEngine.startListening() } }
                    } label: {
                        ZStack {
                            Circle().fill(self.voiceEngine.isListening ? .white.opacity(0.15) : .red.opacity(0.8))
                                .frame(width: 52, height: 52)
                            Image(systemName: self.voiceEngine.isListening ? "mic.fill" : "mic.slash.fill")
                                .font(.title3).foregroundStyle(.white)
                        }
                    }

                    // End call
                    Button {
                        self.voiceEngine.stopListening()
                        self.dismiss()
                    } label: {
                        ZStack {
                            Circle().fill(.red).frame(width: 64, height: 64)
                            Image(systemName: "phone.down.fill").font(.title2).foregroundStyle(.white)
                        }.shadow(color: .red.opacity(0.4), radius: 12, y: 4)
                    }

                    // Placeholder for symmetry
                    Circle().fill(.clear).frame(width: 52, height: 52)
                }
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { Task { await self.voiceEngine.startListening() } }
        .onDisappear { self.voiceEngine.stopListening() }
    }
}

// MARK: - Voice Engine

/// Handles microphone capture and on-device speech recognition for video chat.
/// Provides real-time transcript and mic level to drive the avatar animation.
@MainActor
@Observable
final class VideoChatVoiceEngine: NSObject {
    var isListening = false
    var currentTranscript = ""
    var micLevel: Double = 0
    var statusText = "Tap mic to start"

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false

    func startListening() async {
        guard !self.isListening else { return }

        self.statusText = "Requesting permissions…"

        // Request mic permission
        let micOk = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micOk else { self.statusText = "Microphone denied"; return }

        // Request speech permission
        let speechOk = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOk else { self.statusText = "Speech recognition denied"; return }

        self.speechRecognizer = SFSpeechRecognizer()
        guard self.speechRecognizer != nil else { self.statusText = "Recognizer unavailable"; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            self.recognitionRequest?.shouldReportPartialResults = true

            let input = self.audioEngine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0 else { self.statusText = "Invalid audio format"; return }

            input.removeTap(onBus: 0)
            let request = self.recognitionRequest!
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                // Calculate mic level for avatar animation
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
                        self.currentTranscript = result.bestTranscription.formattedString
                    }
                    if let error {
                        let msg = error.localizedDescription
                        if !msg.localizedCaseInsensitiveContains("no speech detected") {
                            self.statusText = "Error: \(msg)"
                        }
                        // Restart on transient errors
                        if self.isListening {
                            self.stopRecognition()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            if self.isListening { await self.startListening() }
                        }
                    }
                }
            }

            self.isListening = true
            self.statusText = "Listening"
        } catch {
            self.statusText = "Start failed: \(error.localizedDescription)"
        }
    }

    func stopListening() {
        self.isListening = false
        self.statusText = "Tap mic to start"
        self.micLevel = 0
        self.stopRecognition()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func stopRecognition() {
        self.recognitionTask?.cancel()
        self.recognitionTask = nil
        self.recognitionRequest?.endAudio()
        self.recognitionRequest = nil
        if self.inputTapInstalled {
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.inputTapInstalled = false
        }
        self.audioEngine.stop()
        self.speechRecognizer = nil
    }
}
