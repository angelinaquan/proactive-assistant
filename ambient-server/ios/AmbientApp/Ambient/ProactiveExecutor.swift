import Foundation
import OSLog

/// Executes action plans proactively and tracks rollback info for undo.
@MainActor
final class ProactiveExecutor {
    private let logger = Logger(subsystem: "ambient", category: "Executor")
    private let reminders = RemindersService()
    private let calendar = CalendarService()
    let rollbackStore: RollbackStore
    let ambientStore: AmbientStore

    init(rollbackStore: RollbackStore, ambientStore: AmbientStore) {
        self.rollbackStore = rollbackStore
        self.ambientStore = ambientStore
    }

    func processActionPlan(_ item: AmbientActionItem) async {
        self.ambientStore.addItem(item)
        if item.autoExecute { await self.execute(item) }
    }

    func execute(_ item: AmbientActionItem) async {
        var m = item
        do {
            let sysId: String?
            switch item.type {
            case .reminder, .followUp, .commitment:
                sysId = try await self.reminders.add(
                    title: item.actionParams["title"]?.stringValue ?? item.actionDescription,
                    dueISO: item.actionParams["due_iso"]?.stringValue,
                    notes: item.actionParams["notes"]?.stringValue)
            case .calendarEvent:
                sysId = try await self.calendar.add(
                    title: item.actionParams["title"]?.stringValue ?? item.actionDescription,
                    startISO: item.actionParams["start_iso"]?.stringValue ?? ISO8601DateFormatter().string(from: Date()),
                    endISO: item.actionParams["end_iso"]?.stringValue ?? ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                    location: item.actionParams["location"]?.stringValue,
                    notes: item.actionParams["notes"]?.stringValue)
            case .note, .draftMessage:
                sysId = nil
            }
            m.executionStatus = .executed; m.executedAt = Date()
            if let s = sysId { m.executionResult = ["identifier": .string(s)] }
            self.ambientStore.updateItem(m)
            self.rollbackStore.recordExecution(actionPlanId: item.id, type: item.type, systemIdentifier: sysId, undoWindowSeconds: item.undoWindowSeconds)
            self.logger.info("Executed: \(item.actionDescription, privacy: .public)")
        } catch {
            m.executionStatus = .failed; self.ambientStore.updateItem(m)
            self.logger.error("Failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func undo(actionPlanId: String) async -> Bool {
        guard let entry = self.rollbackStore.entry(forActionPlanId: actionPlanId), entry.canUndo else { return false }
        do {
            if let sysId = entry.systemIdentifier {
                switch entry.type {
                case .reminder, .followUp, .commitment: try await self.reminders.delete(identifier: sysId)
                case .calendarEvent: try await self.calendar.delete(identifier: sysId)
                case .note, .draftMessage: break
                }
            }
            self.rollbackStore.markUndone(actionPlanId: actionPlanId)
            if var item = self.ambientStore.item(byId: actionPlanId) {
                item.executionStatus = .undone; item.undoneAt = Date(); self.ambientStore.updateItem(item)
            }
            return true
        } catch { self.logger.error("Undo failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    func confirm(actionPlanId: String) {
        self.rollbackStore.markConfirmed(actionPlanId: actionPlanId)
        if var item = self.ambientStore.item(byId: actionPlanId) {
            item.executionStatus = .confirmed; item.confirmedAt = Date(); self.ambientStore.updateItem(item)
        }
    }

    func discard(actionPlanId: String) {
        self.ambientStore.removeItem(id: actionPlanId)
        self.rollbackStore.removeEntry(actionPlanId: actionPlanId)
    }

    func autoConfirmExpired() {
        self.rollbackStore.autoConfirmExpired()
        self.ambientStore.autoConfirmExpired()
    }
}
