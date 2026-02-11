import Foundation
import Testing
@testable import OpenClaw

@Suite(.serialized) struct RollbackStoreTests {
    @Test @MainActor func recordAndRetrieveEntry() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "plan-1",
            type: .reminder,
            systemIdentifier: "EK-123",
            undoWindowSeconds: 1800)

        let entry = store.entry(forActionPlanId: "plan-1")
        #expect(entry != nil)
        #expect(entry?.type == .reminder)
        #expect(entry?.systemIdentifier == "EK-123")
        #expect(entry?.status == .executed)
        #expect(entry?.canUndo == true)

        store.removeAll()
    }

    @Test @MainActor func markUndone() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "plan-undo",
            type: .calendarEvent,
            systemIdentifier: "EV-456")

        store.markUndone(actionPlanId: "plan-undo")

        let entry = store.entry(forActionPlanId: "plan-undo")
        #expect(entry?.status == .undone)
        #expect(entry?.canUndo == false)

        store.removeAll()
    }

    @Test @MainActor func markConfirmed() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "plan-confirm",
            type: .reminder,
            systemIdentifier: "RM-789")

        store.markConfirmed(actionPlanId: "plan-confirm")

        let entry = store.entry(forActionPlanId: "plan-confirm")
        #expect(entry?.status == .confirmed)
        #expect(entry?.canUndo == false)

        store.removeAll()
    }

    @Test @MainActor func undoableEntries() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "active-1",
            type: .reminder,
            systemIdentifier: "RM-1",
            undoWindowSeconds: 1800)

        store.recordExecution(
            actionPlanId: "active-2",
            type: .calendarEvent,
            systemIdentifier: "EV-2",
            undoWindowSeconds: 1800)

        // Mark one as confirmed
        store.markConfirmed(actionPlanId: "active-2")

        let undoable = store.undoableEntries
        #expect(undoable.count == 1)
        #expect(undoable.first?.actionPlanId == "active-1")

        store.removeAll()
    }

    @Test @MainActor func autoConfirmExpired() {
        let store = RollbackStore()
        store.removeAll()

        // Record with 0-second undo window (already expired)
        store.recordExecution(
            actionPlanId: "expired-plan",
            type: .reminder,
            systemIdentifier: "RM-X",
            undoWindowSeconds: 0)

        // Need a tiny sleep for the window to actually pass
        store.autoConfirmExpired()

        let entry = store.entry(forActionPlanId: "expired-plan")
        #expect(entry?.status == .confirmed)

        store.removeAll()
    }

    @Test @MainActor func removeEntry() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "plan-remove",
            type: .note,
            systemIdentifier: nil)

        #expect(store.entries.count == 1)

        store.removeEntry(actionPlanId: "plan-remove")
        #expect(store.entries.count == 0)
        #expect(store.entry(forActionPlanId: "plan-remove") == nil)

        store.removeAll()
    }

    @Test @MainActor func removeAll() {
        let store = RollbackStore()
        store.recordExecution(actionPlanId: "a", type: .reminder, systemIdentifier: nil)
        store.recordExecution(actionPlanId: "b", type: .reminder, systemIdentifier: nil)

        store.removeAll()
        #expect(store.entries.count == 0)
    }

    @Test @MainActor func undoTimeRemaining() {
        let store = RollbackStore()
        store.removeAll()

        store.recordExecution(
            actionPlanId: "time-check",
            type: .reminder,
            systemIdentifier: "RM-T",
            undoWindowSeconds: 1800)

        let entry = store.entry(forActionPlanId: "time-check")
        #expect(entry != nil)
        // Should have close to 1800 seconds remaining (within 5 seconds tolerance)
        #expect(entry!.undoTimeRemaining > 1790)
        #expect(entry!.undoTimeRemaining <= 1800)

        store.removeAll()
    }

    @Test func rollbackEntryCanUndo() {
        let entry = RollbackEntry(
            actionPlanId: "test",
            type: .reminder,
            systemIdentifier: "RM-1",
            executedAt: Date(),
            undoExpiresAt: Date().addingTimeInterval(1800),
            status: .executed)
        #expect(entry.canUndo == true)

        let expiredEntry = RollbackEntry(
            actionPlanId: "test-old",
            type: .reminder,
            systemIdentifier: "RM-2",
            executedAt: Date().addingTimeInterval(-3600),
            undoExpiresAt: Date().addingTimeInterval(-1800),
            status: .executed)
        #expect(expiredEntry.canUndo == false)

        let confirmedEntry = RollbackEntry(
            actionPlanId: "test-conf",
            type: .reminder,
            systemIdentifier: "RM-3",
            executedAt: Date(),
            undoExpiresAt: Date().addingTimeInterval(1800),
            status: .confirmed)
        #expect(confirmedEntry.canUndo == false)
    }
}
