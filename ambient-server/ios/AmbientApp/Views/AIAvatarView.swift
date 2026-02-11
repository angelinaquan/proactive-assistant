import SwiftUI

/// AI avatar with animated glow rings for speaking/listening/thinking states.
struct AIAvatarView: View {
    let micLevel: Double
    let isSpeaking: Bool
    let isThinking: Bool
    let isListening: Bool
    let statusText: String
    let agentName: String
    let avatarImageURL: URL?
    let accentColor: Color

    @State private var breathePulse = false
    @State private var thinkRotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().stroke(self.outerRingColor.opacity(self.outerRingOpacity), lineWidth: 2)
                    .frame(width: 280, height: 280).scaleEffect(self.outerRingScale)
                    .animation(self.outerRingAnim, value: self.breathePulse)
                Circle().stroke(self.accentColor.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 280, height: 280).scaleEffect(self.breathePulse ? 1.25 : 1.0)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.3), value: self.breathePulse)
                if self.isThinking {
                    Circle().trim(from: 0, to: 0.3).stroke(self.accentColor.opacity(0.6), lineWidth: 2)
                        .frame(width: 260, height: 260).rotationEffect(.degrees(self.thinkRotation))
                }
                self.avatarImage.frame(width: 200, height: 200).clipShape(Circle())
                    .overlay(Circle().stroke(
                        LinearGradient(colors: [self.accentColor.opacity(self.isSpeaking ? 0.7 : 0.3), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: self.isSpeaking ? 3 : 1.5))
                    .scaleEffect(self.isSpeaking ? 1.0 + 0.06 * self.micLevel : 1.0)
                    .shadow(color: self.accentColor.opacity(self.isSpeaking ? 0.4 : 0.15), radius: self.isSpeaking ? 30 : 15)
                    .animation(.easeInOut(duration: 0.15), value: self.micLevel)
            }
            if !self.agentName.isEmpty {
                Text(self.agentName).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            if !self.statusText.isEmpty, self.statusText != "Off" {
                Text(self.statusText).font(.system(.footnote, design: .rounded).weight(.medium)).foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.35)).overlay(Capsule().stroke(self.accentColor.opacity(0.2), lineWidth: 1)))
            }
            if self.isListening {
                Capsule().fill(self.accentColor.opacity(0.85)).frame(width: max(20, 200 * self.micLevel), height: 6)
                    .animation(.easeOut(duration: 0.1), value: self.micLevel)
            }
            Spacer()
        }
        .onAppear {
            self.breathePulse = true
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { self.thinkRotation = 360 }
        }
    }

    @ViewBuilder private var avatarImage: some View {
        if let url = self.avatarImageURL {
            AsyncImage(url: url) { phase in
                if case let .success(img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                else { self.defaultAvatar }
            }
        } else { self.defaultAvatar }
    }

    @ViewBuilder private var defaultAvatar: some View {
        ZStack {
            RadialGradient(colors: [self.accentColor.opacity(0.6), Color.black.opacity(0.5)], center: .center, startRadius: 1, endRadius: 100)
            Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private var outerRingScale: CGFloat { self.isSpeaking ? 1.05 + 0.15 * self.micLevel : (self.breathePulse ? 1.08 : 1.0) }
    private var outerRingOpacity: Double { self.isSpeaking ? 0.4 + 0.3 * self.micLevel : (self.breathePulse ? 0.0 : 0.25) }
    private var outerRingColor: Color { self.isSpeaking ? self.accentColor : .white }
    private var outerRingAnim: Animation { self.isSpeaking ? .easeOut(duration: 0.15) : .easeInOut(duration: 2.5).repeatForever(autoreverses: true) }
}
