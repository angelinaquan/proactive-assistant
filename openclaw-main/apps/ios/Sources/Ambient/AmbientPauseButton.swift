import SwiftUI

/// A prominent, always-visible pause/resume button for ambient listening.
/// Shows listening status with a pulsing animation when active.
struct AmbientPauseButton: View {
    let isListening: Bool
    let isPaused: Bool
    let onToggle: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: self.onToggle) {
            HStack(spacing: 8) {
                ZStack {
                    if self.isListening, !self.isPaused {
                        Circle()
                            .fill(.red.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .scaleEffect(self.pulse ? 1.4 : 1.0)
                            .opacity(self.pulse ? 0.0 : 0.8)
                            .animation(
                                .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                                value: self.pulse)
                    }

                    Circle()
                        .fill(self.dotColor)
                        .frame(width: 10, height: 10)
                }
                .frame(width: 24, height: 24)

                Text(self.buttonText)
                    .font(.caption.weight(.semibold))

                Image(systemName: self.buttonIcon)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(self.borderColor.opacity(0.3), lineWidth: 1)))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            if self.isListening, !self.isPaused {
                self.pulse = true
            }
        }
        .onChange(of: self.isListening) { _, newValue in
            self.pulse = newValue && !self.isPaused
        }
        .onChange(of: self.isPaused) { _, newValue in
            self.pulse = self.isListening && !newValue
        }
    }

    private var dotColor: Color {
        if !self.isListening { return .gray }
        return self.isPaused ? .orange : .red
    }

    private var borderColor: Color {
        if !self.isListening { return .gray }
        return self.isPaused ? .orange : .red
    }

    private var buttonText: String {
        if !self.isListening { return "Ambient Off" }
        return self.isPaused ? "Paused" : "Listening"
    }

    private var buttonIcon: String {
        if !self.isListening { return "mic.slash" }
        return self.isPaused ? "play.fill" : "pause.fill"
    }
}
