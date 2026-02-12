import Foundation
import OSLog
import UserNotifications

/// Executes action plans proactively and tracks rollback info for undo.
///
/// Respects the user's "Auto-Execute Actions" setting: when disabled,
/// all items are stored as suggestions regardless of server confidence.
///
/// Sends a local notification after each auto-executed action so the user
/// knows something was created even when the app is backgrounded.
@MainActor
final class ProactiveExecutor {
    private let logger = Logger(subsystem: "ambient", category: "Executor")
    private let reminders = RemindersService()
    private let calendar = CalendarService()
    let rollbackStore: RollbackStore
    let ambientStore: AmbientStore

    /// Whether auto-execution is allowed. Reads the user's setting.
    /// When `false`, all action plans are stored as suggestions.
    var isAutoExecuteEnabled: Bool {
        // Mirror the @AppStorage("ambient.autoExecute") default of true
        if UserDefaults.standard.object(forKey: "ambient.autoExecute") == nil { return true }
        return UserDefaults.standard.bool(forKey: "ambient.autoExecute")
    }

    init(rollbackStore: RollbackStore, ambientStore: AmbientStore) {
        self.rollbackStore = rollbackStore
        self.ambientStore = ambientStore
    }

    func processActionPlan(_ item: AmbientActionItem) async {
        self.ambientStore.addItem(item)

        // Only auto-execute if BOTH the server says auto_execute AND the user has the setting enabled
        if item.autoExecute && self.isAutoExecuteEnabled {
            await self.execute(item)
        } else if item.autoExecute && !self.isAutoExecuteEnabled {
            self.logger.info("Auto-execute disabled by user; stored as suggestion: \(item.actionDescription, privacy: .public)")
        }
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

            // Send local notification so user knows even when backgrounded
            await self.sendExecutionNotification(for: item)
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

    func edit(actionPlanId: String, title: String, deadline: String, notes: String) {
        guard var item = self.ambientStore.item(byId: actionPlanId) else { return }
        var params = item.actionParams
        if !title.isEmpty { params["title"] = .string(title) }
        if !deadline.isEmpty { params["due_iso"] = .string(deadline) }
        if !notes.isEmpty { params["notes"] = .string(notes) }
        // Rebuild description
        let newDesc = "Edited: \"\(title.isEmpty ? item.actionDescription : title)\""
        item = AmbientActionItem(
            id: item.id, type: item.type, confidence: item.confidence,
            confidenceLevel: item.confidenceLevel, autoExecute: item.autoExecute,
            sourceTranscript: item.sourceTranscript, contextWindow: item.contextWindow,
            actionDescription: newDesc, actionParams: params,
            executionStatus: item.executionStatus, executedAt: item.executedAt,
            executionResult: item.executionResult, detectedAt: item.detectedAt,
            confirmedAt: item.confirmedAt, undoneAt: item.undoneAt,
            people: item.people, deadline: deadline.isEmpty ? item.deadline : deadline,
            undoWindowSeconds: item.undoWindowSeconds)
        self.ambientStore.updateItem(item)
        self.logger.info("Edited: \(actionPlanId, privacy: .public) → \(newDesc, privacy: .public)")
    }

    func discard(actionPlanId: String) {
        self.ambientStore.removeItem(id: actionPlanId)
        self.rollbackStore.removeEntry(actionPlanId: actionPlanId)
    }

    func autoConfirmExpired() {
        self.rollbackStore.autoConfirmExpired()
        self.rollbackStore.cleanupOldEntries()
        self.ambientStore.autoConfirmExpired()
    }

    // MARK: - Notifications

    private func sendExecutionNotification(for item: AmbientActionItem) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .notDetermined else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "✅ Action Created"
        content.body = item.actionDescription
        content.sound = .default
        content.userInfo = ["actionPlanId": item.id]

        let request = UNNotificationRequest(
            identifier: "ambient-\(item.id)",
            content: content,
            trigger: nil) // Deliver immediately

        do {
            try await center.add(request)
            self.logger.info("Notification sent for: \(item.actionDescription, privacy: .public)")
        } catch {
            self.logger.warning("Notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
