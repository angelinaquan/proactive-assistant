import SwiftUI

/// Full-screen AI video chat interface.
///
/// Wraps the existing `TalkModeManager` for all voice I/O (speech recognition,
/// gateway chat, incremental TTS playback) and provides a visual layer with:
/// - AI avatar image with speaking/listening/thinking animations
/// - Live transcript overlay
/// - End call button
///
/// The video is not real video — it's a static/animated AI avatar image.
/// Sub-second response times are achieved via the existing incremental
/// TTS streaming infrastructure (ElevenLabsKit).
struct VideoChatView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var userTranscript: String = ""
    @State private var assistantText: String = ""

    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                self.topBar

                Spacer()

                // AI Avatar (center)
                AIAvatarView(
                    micLevel: self.appModel.talkMode.micLevel,
                    isSpeaking: self.appModel.talkMode.isSpeaking,
                    isThinking: self.isThinking,
                    isListening: self.appModel.talkMode.isListening,
                    statusText: self.appModel.talkMode.statusText,
                    agentName: self.appModel.activeAgentName,
                    avatarImageURL: nil, // TODO: load from gateway config
                    accentColor: self.appModel.seamColor)

                Spacer()

                // Transcript overlay
                VideoChatTranscriptOverlay(
                    userTranscript: self.userTranscript,
                    assistantText: self.assistantText,
                    isListening: self.appModel.talkMode.isListening,
                    isSpeaking: self.appModel.talkMode.isSpeaking)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                // End call button
                self.endCallButton
                    .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            self.startVideoChat()
        }
        .onDisappear {
            self.stopVideoChat()
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Video Chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))

                if self.appModel.talkMode.isEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Button {
                self.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - End Call Button

    @ViewBuilder
    private var endCallButton: some View {
        Button {
            self.stopVideoChat()
            self.dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 64, height: 64)

                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .shadow(color: .red.opacity(0.4), radius: 12, y: 4)
        }
        .accessibilityLabel("End Video Chat")
    }

    // MARK: - Lifecycle

    private func startVideoChat() {
        // Enable talk mode if not already enabled
        if !self.appModel.talkMode.isEnabled {
            self.appModel.setTalkEnabled(true)
        }
    }

    private func stopVideoChat() {
        // Don't disable talk mode on dismiss — let the user control that separately
        // via the talk toggle. Video chat is just a visual layer.
    }

    // MARK: - Computed state

    private var isThinking: Bool {
        let status = self.appModel.talkMode.statusText.lowercased()
        return status.contains("thinking") || status.contains("generating")
    }
}
