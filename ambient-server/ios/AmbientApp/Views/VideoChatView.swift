import AVFAudio
import Speech
import SwiftUI

/// Full-screen AI video chat with avatar and live transcript.
/// Uses on-device speech recognition + ambient server for AI responses.
struct VideoChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var userTranscript: String = ""
    @State private var isRecording = false
    @State private var micLevel: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video Chat").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        if self.isRecording {
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
                    micLevel: self.micLevel, isSpeaking: false, isThinking: false,
                    isListening: self.isRecording,
                    statusText: self.isRecording ? "Listening" : "Tap to start",
                    agentName: "Assistant", avatarImageURL: self.appModel.avatarImageURL,
                    accentColor: .blue)

                Spacer()

                // Transcript
                if !self.userTranscript.isEmpty {
                    Text(self.userTranscript).font(.caption).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.8)))
                        .padding(.horizontal, 16).padding(.bottom, 16)
                }

                // End call
                Button {
                    self.dismiss()
                } label: {
                    ZStack {
                        Circle().fill(.red).frame(width: 64, height: 64)
                        Image(systemName: "phone.down.fill").font(.title2).foregroundStyle(.white)
                    }.shadow(color: .red.opacity(0.4), radius: 12, y: 4)
                }.padding(.bottom, 30)
            }
        }.preferredColorScheme(.dark)
    }
}
