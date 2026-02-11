import Foundation
import Testing
@testable import OpenClaw

@Suite(.serialized) struct AmbientStoreTests {
    private func makeItem(
        id: String = "test-\(UUID().uuidString)",
        type: AmbientActionType = .reminder,
        confidence: Double = 0.85,
        autoExecute: Bool = true,
        status: AmbientExecutionStatus = .pending,
        executedAt: Date? = nil
    ) -> AmbientActionItem {
        AmbientActionItem(
            id: id,
            type: type,
            confidence: confidence,
            confidenceLevel: confidence >= 0.8 ? .high : .medium,
            autoExecute: autoExecute,
            sourceTranscript: "test transcript",
            contextWindow: "context",
            actionDescription: "Test action: \(id)",
            actionParams: ["title": .string("Test")],
            executionStatus: status,
            executedAt: executedAt,
            executionResult: nil,
            detectedAt: Date(),
            confirmedAt: nil,
            undoneAt: nil,
            people: [],
            deadline: nil,
            undoWindowSeconds: 1800)
    }

    @Test @MainActor func addAndRetrieveItem() {
        let store = AmbientStore()
        store.deleteAll()

        let item = self.makeItem(id: "item-1")
        store.addItem(item)

        #expect(store.items.count == 1)
        #expect(store.item(byId: "item-1") != nil)
        #expect(store.item(byId: "item-1")?.id == "item-1")

        store.deleteAll()
    }

    @Test @MainActor func updateItem() {
        let store = AmbientStore()
        store.deleteAll()

        var item = self.makeItem(id: "item-update")
        store.addItem(item)

        item.executionStatus = .executed
        item.executedAt = Date()
        store.updateItem(item)

        let updated = store.item(byId: "item-update")
        #expect(updated?.executionStatus == .executed)
        #expect(updated?.executedAt != nil)

        store.deleteAll()
    }

    @Test @MainActor func removeItem() {
        let store = AmbientStore()
        store.deleteAll()

        store.addItem(self.makeItem(id: "item-remove"))
        #expect(store.items.count == 1)

        store.removeItem(id: "item-remove")
        #expect(store.items.count == 0)
        #expect(store.item(byId: "item-remove") == nil)

        store.deleteAll()
    }

    @Test @MainActor func executedItemsFilter() {
        let store = AmbientStore()
        store.deleteAll()

        store.addItem(self.makeItem(id: "exec-1", status: .executed, executedAt: Date()))
        store.addItem(self.makeItem(id: "exec-2", status: .executed, executedAt: Date()))
        store.addItem(self.makeItem(id: "pend-1", status: .pending, autoExecute: false))

        #expect(store.executedItems.count == 2)
        #expect(store.suggestions.count == 1)

        store.deleteAll()
    }

    @Test @MainActor func pendingCount() {
        let store = AmbientStore()
        store.deleteAll()

        store.addItem(self.makeItem(id: "e1", status: .executed, executedAt: Date()))
        store.addItem(self.makeItem(id: "s1", status: .pending, autoExecute: false))
        store.addItem(self.makeItem(id: "c1", status: .confirmed))

        // pendingCount = executed (not confirmed) + suggestions
        #expect(store.pendingCount == 2)

        store.deleteAll()
    }

    @Test @MainActor func deleteAll() {
        let store = AmbientStore()
        store.addItem(self.makeItem(id: "a"))
        store.addItem(self.makeItem(id: "b"))
        store.addItem(self.makeItem(id: "c"))

        store.deleteAll()
        #expect(store.items.count == 0)
    }

    @Test @MainActor func autoConfirmExpired() {
        let store = AmbientStore()
        store.deleteAll()

        // Item with undo window already expired (executedAt far in the past)
        var item = self.makeItem(id: "expired", status: .executed)
        item.executedAt = Date().addingTimeInterval(-3600) // 1 hour ago
        store.addItem(item)

        store.autoConfirmExpired()

        let updated = store.item(byId: "expired")
        #expect(updated?.executionStatus == .confirmed)
        #expect(updated?.confirmedAt != nil)

        store.deleteAll()
    }

    @Test @MainActor func canUndoProperty() {
        var item = self.makeItem(id: "undo-test", status: .executed)
        item.executedAt = Date() // Just now
        #expect(item.canUndo == true)
        #expect(item.undoTimeRemaining > 0)

        // Item executed long ago
        var oldItem = self.makeItem(id: "old-undo", status: .executed)
        oldItem.executedAt = Date().addingTimeInterval(-3600)
        #expect(oldItem.canUndo == false)
        #expect(oldItem.undoTimeRemaining == 0)

        // Item not executed
        let pendingItem = self.makeItem(id: "not-exec", status: .pending)
        #expect(pendingItem.canUndo == false)
    }
}
