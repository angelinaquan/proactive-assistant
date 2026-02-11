import SwiftUI

/// Detail view for a single ambient action item, showing the full audit trail:
/// what was heard, what the system interpreted, and what action was taken.
struct AmbientItemDetailView: View {
    let item: AmbientActionItem
    let onKeep: () -> Void
    let onUndo: () -> Void
    let onExecute: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                self.headerSection

                Divider()

                // Audit Trail
                self.auditTrailSection

                Divider()

                // Details
                self.detailsSection

                // Actions
                self.actionsSection
            }
            .padding()
        }
        .navigationTitle("Action Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                self.typeIcon
                    .font(.title2)
                    .foregroundStyle(self.statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.item.actionDescription)
                        .font(.headline)

                    Text(self.item.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                self.statusPill
                self.confidencePill
            }
        }
    }

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

    private var statusColor: Color {
        switch self.item.executionStatus {
        case .executed: .green
        case .confirmed: .blue
        case .undone: .gray
        case .failed: .red
        case .pending: .orange
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let (text, color) = self.statusLabel
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }

    private var statusLabel: (String, Color) {
        switch self.item.executionStatus {
        case .executed: ("Executed", .green)
        case .confirmed: ("Confirmed", .blue)
        case .undone: ("Undone", .gray)
        case .failed: ("Failed", .red)
        case .pending: ("Suggestion", .orange)
        }
    }

    @ViewBuilder
    private var confidencePill: some View {
        let pct = Int(self.item.confidence * 100)
        Text("Confidence: \(pct)%")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Audit Trail

    @ViewBuilder
    private var auditTrailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audit Trail")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Step 1: Heard
            AuditStep(
                icon: "mic.fill",
                color: .purple,
                title: "Heard",
                detail: self.item.sourceTranscript.isEmpty ? "(no transcript)" : self.item.sourceTranscript)

            // Step 2: Interpreted
            AuditStep(
                icon: "brain",
                color: .blue,
                title: "Interpreted",
                detail: self.item.actionDescription)

            // Step 3: Action
            if self.item.executionStatus == .executed || self.item.executionStatus == .confirmed {
                let timeText = self.item.executedAt.map { self.formatDate($0) } ?? ""
                AuditStep(
                    icon: "bolt.fill",
                    color: .green,
                    title: "Action Taken",
                    detail: "\(self.item.actionDescription)\(timeText.isEmpty ? "" : " at \(timeText)")")
            } else if self.item.executionStatus == .pending {
                AuditStep(
                    icon: "lightbulb.fill",
                    color: .orange,
                    title: "Suggested",
                    detail: "Waiting for your decision")
            } else if self.item.executionStatus == .undone {
                let timeText = self.item.undoneAt.map { self.formatDate($0) } ?? ""
                AuditStep(
                    icon: "arrow.uturn.backward",
                    color: .gray,
                    title: "Undone",
                    detail: "Action was reversed\(timeText.isEmpty ? "" : " at \(timeText)")")
            }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !self.item.people.isEmpty {
                DetailRow(label: "People", value: self.item.people.joined(separator: ", "))
            }

            if let deadline = self.item.deadline {
                DetailRow(label: "Deadline", value: deadline)
            }

            DetailRow(label: "Detected", value: self.formatDate(self.item.detectedAt))

            if self.item.canUndo {
                let minutes = Int(self.item.undoTimeRemaining / 60)
                DetailRow(label: "Undo window", value: "\(minutes) minutes remaining")
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        switch self.item.executionStatus {
        case .executed:
            VStack(spacing: 12) {
                Button {
                    self.onKeep()
                } label: {
                    Label("Keep This Action", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if self.item.canUndo {
                    Button(role: .destructive) {
                        self.onUndo()
                    } label: {
                        Label("Undo This Action", systemImage: "arrow.uturn.backward.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 8)

        case .pending:
            VStack(spacing: 12) {
                Button {
                    self.onExecute()
                } label: {
                    Label("Create This Action", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    self.onDiscard()
                } label: {
                    Label("Discard", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)

        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Subviews

private struct AuditStep: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.color)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(self.color.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(self.color)

                Text(self.detail)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(self.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(self.value)
                .font(.caption)
        }
    }
}
