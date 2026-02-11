import SwiftUI

/// A single row in the ambient timeline, showing an action item with its status
/// and available actions (Keep, Edit, Undo for executed items; Execute, Discard for suggestions).
struct AmbientItemRow: View {
    let item: AmbientActionItem
    let onKeep: () -> Void
    let onUndo: () -> Void
    let onExecute: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                self.typeIcon
                    .font(.system(size: 20))
                    .foregroundStyle(self.iconColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(self.item.actionDescription)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        self.statusBadge

                        self.confidenceBadge

                        Text(self.timeAgo)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !self.item.people.isEmpty {
                        Text("People: \(self.item.people.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // Action buttons
            self.actionButtons
        }
        .padding(.vertical, 6)
    }

    // MARK: - Type Icon

    @ViewBuilder
    private var typeIcon: some View {
        switch self.item.type {
        case .reminder, .commitment, .followUp:
            Image(systemName: "bell.fill")
        case .calendarEvent:
            Image(systemName: "calendar.badge.plus")
        case .note:
            Image(systemName: "note.text")
        case .draftMessage:
            Image(systemName: "envelope.fill")
        }
    }

    private var iconColor: Color {
        switch self.item.executionStatus {
        case .executed:
            return .green
        case .confirmed:
            return .blue
        case .undone:
            return .gray
        case .failed:
            return .red
        case .pending:
            return .orange
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color) = self.statusInfo
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15)))
    }

    private var statusInfo: (String, Color) {
        switch self.item.executionStatus {
        case .executed:
            if self.item.canUndo {
                let minutes = Int(self.item.undoTimeRemaining / 60)
                return ("Done · \(minutes)m to undo", .green)
            }
            return ("Done", .green)
        case .confirmed:
            return ("Confirmed", .blue)
        case .undone:
            return ("Undone", .gray)
        case .failed:
            return ("Failed", .red)
        case .pending:
            return ("Suggestion", .orange)
        }
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        let pct = Int(self.item.confidence * 100)
        Text("\(pct)%")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Time

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self.item.detectedAt, relativeTo: Date())
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch self.item.executionStatus {
        case .executed:
            HStack(spacing: 12) {
                Button {
                    self.onKeep()
                } label: {
                    Label("Keep", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.green)

                if self.item.canUndo {
                    Button {
                        self.onUndo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.leading, 38)

        case .pending:
            HStack(spacing: 12) {
                Button {
                    self.onExecute()
                } label: {
                    Label("Create", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.blue)

                Button {
                    self.onDiscard()
                } label: {
                    Label("Discard", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
            }
            .padding(.leading, 38)

        case .confirmed, .undone, .failed:
            EmptyView()
        }
    }
}
