import SwiftUI

/// Timeline view showing all ambient actions grouped into "Done" (auto-executed)
/// and "Suggestions" (lower confidence, awaiting user decision) sections.
struct AmbientTimelineView: View {
    let items: [AmbientActionItem]
    let onKeep: (String) -> Void
    let onUndo: (String) -> Void
    let onExecute: (String) -> Void
    let onDiscard: (String) -> Void

    var body: some View {
        if self.items.isEmpty {
            self.emptyState
        } else {
            List {
                if !self.executedItems.isEmpty {
                    Section {
                        ForEach(self.executedItems) { item in
                            NavigationLink {
                                AmbientItemDetailView(
                                    item: item,
                                    onKeep: { self.onKeep(item.id) },
                                    onUndo: { self.onUndo(item.id) },
                                    onExecute: { self.onExecute(item.id) },
                                    onDiscard: { self.onDiscard(item.id) })
                            } label: {
                                AmbientItemRow(
                                    item: item,
                                    onKeep: { self.onKeep(item.id) },
                                    onUndo: { self.onUndo(item.id) },
                                    onExecute: { self.onExecute(item.id) },
                                    onDiscard: { self.onDiscard(item.id) })
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Done")
                        }
                    }
                }

                if !self.suggestions.isEmpty {
                    Section {
                        ForEach(self.suggestions) { item in
                            NavigationLink {
                                AmbientItemDetailView(
                                    item: item,
                                    onKeep: { self.onKeep(item.id) },
                                    onUndo: { self.onUndo(item.id) },
                                    onExecute: { self.onExecute(item.id) },
                                    onDiscard: { self.onDiscard(item.id) })
                            } label: {
                                AmbientItemRow(
                                    item: item,
                                    onKeep: { self.onKeep(item.id) },
                                    onUndo: { self.onUndo(item.id) },
                                    onExecute: { self.onExecute(item.id) },
                                    onDiscard: { self.onDiscard(item.id) })
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.orange)
                            Text("Suggestions")
                        }
                    }
                }

                if !self.confirmedItems.isEmpty {
                    Section {
                        ForEach(self.confirmedItems) { item in
                            NavigationLink {
                                AmbientItemDetailView(
                                    item: item,
                                    onKeep: {},
                                    onUndo: {},
                                    onExecute: {},
                                    onDiscard: {})
                            } label: {
                                AmbientItemRow(
                                    item: item,
                                    onKeep: {},
                                    onUndo: {},
                                    onExecute: {},
                                    onDiscard: {})
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                            Text("Confirmed")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Filtered items

    private var executedItems: [AmbientActionItem] {
        self.items
            .filter { $0.executionStatus == .executed }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    private var suggestions: [AmbientActionItem] {
        self.items
            .filter { $0.executionStatus == .pending && !$0.autoExecute }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    private var confirmedItems: [AmbientActionItem] {
        self.items
            .filter { $0.executionStatus == .confirmed }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Actions Yet")
                .font(.headline)

            Text("When ambient listening is active, detected tasks, reminders, and commitments will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
