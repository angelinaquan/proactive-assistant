import SwiftUI

/// AI avatar image with animated states for speaking, listening, and thinking.
///
/// Replaces `TalkOrbOverlay` when in video chat mode. The avatar is a circular
/// image (configurable) with glow rings and scale animations driven by audio levels.
struct AIAvatarView: View {
    /// 0..1 mic level for listening animation
    let micLevel: Double
    /// Whether the AI is currently speaking
    let isSpeaking: Bool
    /// Whether the AI is generating a response
    let isThinking: Bool
    /// Whether the mic is actively capturing
    let isListening: Bool
    /// Status text to display below avatar
    let statusText: String
    /// Agent/bot name
    let agentName: String
    /// Optional custom avatar image URL
    let avatarImageURL: URL?
    /// Accent color for glow effects
    let accentColor: Color

    @State private var breathePulse = false
    @State private var speakPulse = false
    @State private var thinkRotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Avatar with glow rings
            ZStack {
                // Outer glow ring (breathing / speaking)
                Circle()
                    .stroke(self.outerRingColor.opacity(self.outerRingOpacity), lineWidth: 2)
                    .frame(width: 280, height: 280)
                    .scaleEffect(self.outerRingScale)
                    .animation(self.outerRingAnimation, value: self.breathePulse)
                    .animation(self.outerRingAnimation, value: self.speakPulse)

                // Second glow ring
                Circle()
                    .stroke(self.accentColor.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 280, height: 280)
                    .scaleEffect(self.secondRingScale)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.3), value: self.breathePulse)

                // Thinking spinner
                if self.isThinking {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(self.accentColor.opacity(0.6), lineWidth: 2)
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(self.thinkRotation))
                }

                // Avatar image
                self.avatarImage
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        self.accentColor.opacity(self.isSpeaking ? 0.7 : 0.3),
                                        self.accentColor.opacity(self.isSpeaking ? 0.4 : 0.1),
                                        .clear,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: self.isSpeaking ? 3 : 1.5))
                    .scaleEffect(self.avatarScale)
                    .shadow(
                        color: self.accentColor.opacity(self.isSpeaking ? 0.4 : 0.15),
                        radius: self.isSpeaking ? 30 : 15)
                    .animation(.easeInOut(duration: 0.15), value: self.micLevel)
            }

            // Agent name
            if !self.agentName.isEmpty {
                Text(self.agentName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Status text
            if !self.statusText.isEmpty, self.statusText != "Off" {
                Text(self.statusText)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.35))
                            .overlay(
                                Capsule().stroke(self.accentColor.opacity(0.2), lineWidth: 1)))
            }

            // Mic level indicator
            if self.isListening {
                Capsule()
                    .fill(self.accentColor.opacity(0.85))
                    .frame(width: max(20, 200 * self.micLevel), height: 6)
                    .animation(.easeOut(duration: 0.1), value: self.micLevel)
                    .accessibilityLabel("Microphone level")
            }

            Spacer()
        }
        .onAppear {
            self.breathePulse = true
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                self.thinkRotation = 360
            }
        }
        .onChange(of: self.isSpeaking) { _, newValue in
            self.speakPulse = newValue
        }
    }

    // MARK: - Avatar Image

    @ViewBuilder
    private var avatarImage: some View {
        if let url = self.avatarImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    self.defaultAvatar
                default:
                    self.defaultAvatar
                }
            }
        } else {
            self.defaultAvatar
        }
    }

    @ViewBuilder
    private var defaultAvatar: some View {
        ZStack {
            RadialGradient(
                colors: [
                    self.accentColor.opacity(0.6),
                    self.accentColor.opacity(0.3),
                    Color.black.opacity(0.5),
                ],
                center: .center,
                startRadius: 1,
                endRadius: 100)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Animation values

    private var avatarScale: CGFloat {
        if self.isSpeaking {
            return 1.0 + (0.06 * self.micLevel)
        }
        return 1.0
    }

    private var outerRingScale: CGFloat {
        if self.isSpeaking {
            return 1.05 + (0.15 * self.micLevel)
        }
        return self.breathePulse ? 1.08 : 1.0
    }

    private var outerRingOpacity: Double {
        if self.isSpeaking {
            return 0.4 + (0.3 * self.micLevel)
        }
        return self.breathePulse ? 0.0 : 0.25
    }

    private var outerRingColor: Color {
        self.isSpeaking ? self.accentColor : .white
    }

    private var outerRingAnimation: Animation {
        if self.isSpeaking {
            return .easeOut(duration: 0.15)
        }
        return .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
    }

    private var secondRingScale: CGFloat {
        self.breathePulse ? 1.25 : 1.0
    }
}
