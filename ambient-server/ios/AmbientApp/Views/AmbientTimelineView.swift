import SwiftUI

/// Timeline showing Done, Suggestions, and Confirmed sections.
struct AmbientTimelineView: View {
    let items: [AmbientActionItem]
    let onKeep: (String) -> Void
    let onUndo: (String) -> Void
    let onExecute: (String) -> Void
    let onDiscard: (String) -> Void
    var onEdit: ((String, String, String, String) -> Void)? = nil // (id, title, deadline, notes)

    var body: some View {
        if self.items.isEmpty { self.emptyState }
        else {
            List {
                if !self.executed.isEmpty {
                    Section { ForEach(self.executed) { item in self.row(item) } } header: {
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Done") }
                    }
                }
                if !self.suggestions.isEmpty {
                    Section { ForEach(self.suggestions) { item in self.row(item) } } header: {
                        HStack { Image(systemName: "lightbulb.fill").foregroundStyle(.orange); Text("Suggestions") }
                    }
                }
                if !self.confirmed.isEmpty {
                    Section { ForEach(self.confirmed) { item in self.row(item) } } header: {
                        HStack { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue); Text("Confirmed") }
                    }
                }
            }.listStyle(.insetGrouped)
        }
    }

    @ViewBuilder private func row(_ item: AmbientActionItem) -> some View {
        NavigationLink {
            AmbientItemDetailView(item: item, onKeep: { self.onKeep(item.id) }, onUndo: { self.onUndo(item.id) },
                                  onExecute: { self.onExecute(item.id) }, onDiscard: { self.onDiscard(item.id) },
                                  onEdit: self.onEdit.map { editFn in { title, deadline, notes in editFn(item.id, title, deadline, notes) } })
        } label: {
            AmbientItemRow(item: item, onKeep: { self.onKeep(item.id) }, onUndo: { self.onUndo(item.id) },
                           onExecute: { self.onExecute(item.id) }, onDiscard: { self.onDiscard(item.id) })
        }
    }

    private var executed: [AmbientActionItem] { self.items.filter { $0.executionStatus == .executed }.sorted { $0.detectedAt > $1.detectedAt } }
    private var suggestions: [AmbientActionItem] { self.items.filter { $0.executionStatus == .pending && !$0.autoExecute }.sorted { $0.detectedAt > $1.detectedAt } }
    private var confirmed: [AmbientActionItem] { self.items.filter { $0.executionStatus == .confirmed }.sorted { $0.detectedAt > $1.detectedAt } }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Actions Yet").font(.headline)
            Text("When ambient listening is active, detected tasks and reminders will appear here.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
