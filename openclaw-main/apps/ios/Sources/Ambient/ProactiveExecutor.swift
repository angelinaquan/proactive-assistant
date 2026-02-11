import EventKit
import Foundation
import OpenClawKit
import OSLog

/// Executes action plans proactively against iOS services and tracks
/// rollback information for undo capability.
///
/// When a high-confidence action plan arrives from the ambient server,
/// `ProactiveExecutor` immediately creates the reminder, calendar event,
/// or other item. It stores the system identifier in `RollbackStore` so
/// the user can undo the action within the configured time window.
@MainActor
final class ProactiveExecutor {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "ProactiveExecutor")

    private let remindersService: any RemindersServicing
    private let calendarService: any CalendarServicing
    private let rollbackStore: RollbackStore
    private let ambientStore: AmbientStore

    init(
        remindersService: any RemindersServicing,
        calendarService: any CalendarServicing,
        rollbackStore: RollbackStore,
        ambientStore: AmbientStore)
    {
        self.remindersService = remindersService
        self.calendarService = calendarService
        self.rollbackStore = rollbackStore
        self.ambientStore = ambientStore
    }

    // MARK: - Execute

    /// Execute an action plan. Only processes plans with `autoExecute == true`.
    /// Suggestions (autoExecute == false) are stored without execution.
    func processActionPlan(_ item: AmbientActionItem) async {
        // Store in ambient store regardless
        self.ambientStore.addItem(item)

        if item.autoExecute {
            await self.execute(item)
        } else {
            self.logger.info("Stored suggestion: \(item.actionDescription, privacy: .public)")
        }
    }

    /// Execute a specific action plan (e.g., when user approves a suggestion).
    func execute(_ item: AmbientActionItem) async {
        var mutableItem = item

        do {
            let systemIdentifier: String?

            switch item.type {
            case .reminder, .followUp, .commitment:
                systemIdentifier = try await self.executeReminder(item)

            case .calendarEvent:
                systemIdentifier = try await self.executeCalendarEvent(item)

            case .note:
                systemIdentifier = nil
                // Notes are just stored locally, no iOS service needed

            case .draftMessage:
                systemIdentifier = nil
                // Draft messages are stored as suggestions for now
            }

            // Mark as executed
            mutableItem.executionStatus = .executed
            mutableItem.executedAt = Date()
            if let sysId = systemIdentifier {
                mutableItem.executionResult = ["identifier": .string(sysId)]
            }
            self.ambientStore.updateItem(mutableItem)

            // Record rollback info
            self.rollbackStore.recordExecution(
                actionPlanId: item.id,
                type: item.type,
                systemIdentifier: systemIdentifier,
                undoWindowSeconds: item.undoWindowSeconds)

            self.logger.info(
                "Executed: \(item.actionDescription, privacy: .public) [sysId=\(systemIdentifier ?? "nil", privacy: .public)]")

        } catch {
            mutableItem.executionStatus = .failed
            self.ambientStore.updateItem(mutableItem)
            self.logger.error(
                "Execute failed: \(item.actionDescription, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Undo

    /// Undo a previously executed action by deleting the created item.
    func undo(actionPlanId: String) async -> Bool {
        guard let entry = self.rollbackStore.entry(forActionPlanId: actionPlanId) else {
            self.logger.warning("No rollback entry for: \(actionPlanId, privacy: .public)")
            return false
        }

        guard entry.canUndo else {
            self.logger.warning("Undo window expired for: \(actionPlanId, privacy: .public)")
            return false
        }

        do {
            if let sysId = entry.systemIdentifier {
                switch entry.type {
                case .reminder, .followUp, .commitment:
                    try await self.remindersService.delete(identifier: sysId)

                case .calendarEvent:
                    try await self.calendarService.delete(identifier: sysId)

                case .note, .draftMessage:
                    break // Local-only, just remove from store
                }
            }

            // Update stores
            self.rollbackStore.markUndone(actionPlanId: actionPlanId)

            if var item = self.ambientStore.item(byId: actionPlanId) {
                item.executionStatus = .undone
                item.undoneAt = Date()
                self.ambientStore.updateItem(item)
            }

            self.logger.info("Undone: \(actionPlanId, privacy: .public)")
            return true

        } catch {
            self.logger.error(
                "Undo failed for \(actionPlanId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Confirm

    /// Confirm an executed action (user explicitly keeps it).
    func confirm(actionPlanId: String) {
        self.rollbackStore.markConfirmed(actionPlanId: actionPlanId)

        if var item = self.ambientStore.item(byId: actionPlanId) {
            item.executionStatus = .confirmed
            item.confirmedAt = Date()
            self.ambientStore.updateItem(item)
        }
    }

    /// Auto-confirm actions whose undo window has expired.
    func autoConfirmExpired() {
        self.rollbackStore.autoConfirmExpired()
        self.ambientStore.autoConfirmExpired()
    }

    // MARK: - Discard

    /// Discard a suggestion (not executed, just remove from queue).
    func discard(actionPlanId: String) {
        self.ambientStore.removeItem(id: actionPlanId)
        self.rollbackStore.removeEntry(actionPlanId: actionPlanId)
    }

    // MARK: - Private execution methods

    private func executeReminder(_ item: AmbientActionItem) async throws -> String? {
        let title = item.actionParams["title"]?.stringValue ?? item.actionDescription
        let dueISO = item.actionParams["due_iso"]?.stringValue
        let notes = item.actionParams["notes"]?.stringValue

        let params = OpenClawRemindersAddParams(
            title: title,
            dueISO: dueISO,
            notes: notes)

        let result = try await self.remindersService.add(params: params)
        return result.reminder.identifier
    }

    private func executeCalendarEvent(_ item: AmbientActionItem) async throws -> String? {
        let title = item.actionParams["title"]?.stringValue ?? item.actionDescription
        let startISO = item.actionParams["start_iso"]?.stringValue ?? ISO8601DateFormatter().string(from: Date())
        let endISO = item.actionParams["end_iso"]?.stringValue ??
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let location = item.actionParams["location"]?.stringValue
        let notes = item.actionParams["notes"]?.stringValue
        let isAllDay = item.actionParams["is_all_day"]?.boolValue ?? false

        let params = OpenClawCalendarAddParams(
            title: title,
            startISO: startISO,
            endISO: endISO,
            isAllDay: isAllDay,
            location: location,
            notes: notes)

        let result = try await self.calendarService.add(params: params)
        return result.event.identifier
    }
}
