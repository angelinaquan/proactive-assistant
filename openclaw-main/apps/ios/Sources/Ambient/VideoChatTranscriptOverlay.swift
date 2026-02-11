import SwiftUI

/// Live transcript overlay shown at the bottom of the video chat view.
/// Displays what the user said and what the AI is responding.
struct VideoChatTranscriptOverlay: View {
    let userTranscript: String
    let assistantText: String
    let isListening: Bool
    let isSpeaking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !self.userTranscript.isEmpty {
                TranscriptBubble(
                    role: "You",
                    text: self.userTranscript,
                    isActive: self.isListening,
                    alignment: .trailing,
                    color: .blue)
            }

            if !self.assistantText.isEmpty {
                TranscriptBubble(
                    role: "AI",
                    text: self.assistantText,
                    isActive: self.isSpeaking,
                    alignment: .leading,
                    color: .green)
            }

            if self.userTranscript.isEmpty, self.assistantText.isEmpty {
                HStack {
                    Spacer()
                    Text(self.isListening ? "Listening…" : "Tap to speak")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)))
    }
}

private struct TranscriptBubble: View {
    let role: String
    let text: String
    let isActive: Bool
    let alignment: HorizontalAlignment
    let color: Color

    var body: some View {
        VStack(alignment: self.alignment == .trailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 4) {
                if self.isActive {
                    Circle()
                        .fill(self.color)
                        .frame(width: 6, height: 6)
                }
                Text(self.role)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(self.color.opacity(0.8))
            }

            Text(self.text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
                .multilineTextAlignment(self.alignment == .trailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: self.alignment == .trailing ? .trailing : .leading)
    }
}
