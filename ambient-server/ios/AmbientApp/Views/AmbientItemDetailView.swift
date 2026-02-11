import SwiftUI

/// Detail view with full audit trail: Heard → Interpreted → Action Taken.
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
                HStack(spacing: 10) {
                    Image(systemName: self.item.type == .calendarEvent ? "calendar.badge.plus" : "bell.fill")
                        .font(.title2).foregroundStyle(self.statusColor)
                    VStack(alignment: .leading) {
                        Text(self.item.actionDescription).font(.headline)
                        Text(self.item.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(self.statusLabel).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(self.statusColor))
                    Text("Confidence: \(Int(self.item.confidence * 100))%").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
                }

                Divider()

                // Audit trail
                VStack(alignment: .leading, spacing: 14) {
                    Text("Audit Trail").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    AuditStep(icon: "mic.fill", color: .purple, title: "Heard",
                              detail: self.item.sourceTranscript.isEmpty ? "(no transcript)" : self.item.sourceTranscript)
                    AuditStep(icon: "brain", color: .blue, title: "Interpreted", detail: self.item.actionDescription)
                    if self.item.executionStatus == .executed || self.item.executionStatus == .confirmed {
                        AuditStep(icon: "bolt.fill", color: .green, title: "Action Taken", detail: self.item.actionDescription)
                    } else if self.item.executionStatus == .pending {
                        AuditStep(icon: "lightbulb.fill", color: .orange, title: "Suggested", detail: "Waiting for your decision")
                    } else if self.item.executionStatus == .undone {
                        AuditStep(icon: "arrow.uturn.backward", color: .gray, title: "Undone", detail: "Action was reversed")
                    }
                }

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 10) {
                    Text("Details").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    if !self.item.people.isEmpty { DetailRow(label: "People", value: self.item.people.joined(separator: ", ")) }
                    if let deadline = self.item.deadline { DetailRow(label: "Deadline", value: deadline) }
                    if self.item.canUndo { DetailRow(label: "Undo window", value: "\(Int(self.item.undoTimeRemaining / 60)) min remaining") }
                }

                // Actions
                self.actionsSection
            }.padding()
        }.navigationTitle("Action Detail").navigationBarTitleDisplayMode(.inline)
    }

    private var statusColor: Color {
        switch self.item.executionStatus {
        case .executed: .green; case .confirmed: .blue; case .undone: .gray; case .failed: .red; case .pending: .orange
        }
    }

    private var statusLabel: String {
        switch self.item.executionStatus {
        case .executed: "Executed"; case .confirmed: "Confirmed"; case .undone: "Undone"; case .failed: "Failed"; case .pending: "Suggestion"
        }
    }

    @ViewBuilder private var actionsSection: some View {
        switch self.item.executionStatus {
        case .executed:
            VStack(spacing: 12) {
                Button { self.onKeep() } label: { Label("Keep", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.green)
                if self.item.canUndo { Button(role: .destructive) { self.onUndo() } label: { Label("Undo", systemImage: "arrow.uturn.backward.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
            }.padding(.top, 8)
        case .pending:
            VStack(spacing: 12) {
                Button { self.onExecute() } label: { Label("Create", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                Button(role: .destructive) { self.onDiscard() } label: { Label("Discard", systemImage: "xmark.circle").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }.padding(.top, 8)
        default: EmptyView()
        }
    }
}

private struct AuditStep: View {
    let icon: String; let color: Color; let title: String; let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(self.color)
                .frame(width: 24, height: 24).background(Circle().fill(self.color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title).font(.caption.weight(.semibold)).foregroundStyle(self.color)
                Text(self.detail).font(.caption)
            }
        }
    }
}

private struct DetailRow: View {
    let label: String; let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(self.label).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(self.value).font(.caption)
        }
    }
}
