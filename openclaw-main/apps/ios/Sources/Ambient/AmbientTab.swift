import SwiftUI

/// Main ambient listening review screen. Shows the timeline of proactively
/// executed actions and suggestions, with controls for pause/resume and privacy.
struct AmbientTab: View {
    @Environment(\.dismiss) private var dismiss
    let ambientStore: AmbientStore
    let proactiveExecutor: ProactiveExecutor
    let ambientManager: AmbientListeningManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pause button at top
                HStack {
                    AmbientPauseButton(
                        isListening: self.ambientManager.isListening,
                        isPaused: self.ambientManager.isPaused,
                        onToggle: {
                            if self.ambientManager.isPaused {
                                Task { await self.ambientManager.resume() }
                            } else if self.ambientManager.isListening {
                                self.ambientManager.pause()
                            }
                        })

                    Spacer()

                    if !self.ambientManager.lastTranscript.isEmpty {
                        Text(self.ambientManager.lastTranscript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Timeline
                AmbientTimelineView(
                    items: self.ambientStore.items,
                    onKeep: { id in
                        self.proactiveExecutor.confirm(actionPlanId: id)
                    },
                    onUndo: { id in
                        Task {
                            _ = await self.proactiveExecutor.undo(actionPlanId: id)
                        }
                    },
                    onExecute: { id in
                        Task {
                            if let item = self.ambientStore.item(byId: id) {
                                await self.proactiveExecutor.execute(item)
                            }
                        }
                    },
                    onDiscard: { id in
                        self.proactiveExecutor.discard(actionPlanId: id)
                    })
            }
            .navigationTitle("Ambient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AmbientPrivacyView(
                            itemCount: self.ambientStore.items.count,
                            onDeleteToday: {
                                self.ambientStore.deleteAllFromToday()
                            },
                            onDeleteAll: {
                                self.ambientStore.deleteAll()
                            })
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                    .accessibilityLabel("Privacy")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
