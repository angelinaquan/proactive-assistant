import EventKit
import Foundation

/// Standalone reminders service — creates and deletes reminders using EventKit.
/// No external framework dependencies.
final class RemindersService: Sendable {

    func add(title: String, dueISO: String? = nil, notes: String? = nil) async throws -> String {
        let store = EKEventStore()
        try await Self.ensureAccess(store: store)

        let reminder = EKReminder(eventStore: store)
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            reminder.notes = notes
        }
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let dueISO = dueISO?.trimmingCharacters(in: .whitespacesAndNewlines), !dueISO.isEmpty {
            let formatter = ISO8601DateFormatter()
            if let dueDate = formatter.date(from: dueISO) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: dueDate)
            }
        }

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func delete(identifier: String) async throws {
        let store = EKEventStore()
        try await Self.ensureAccess(store: store)

        let predicate = store.predicateForReminders(in: nil)
        let reminder: EKReminder? = try await withCheckedThrowingContinuation { cont in
            store.fetchReminders(matching: predicate) { items in
                cont.resume(returning: (items ?? []).first { $0.calendarItemIdentifier == identifier })
            }
        }
        guard let reminder else {
            throw NSError(domain: "Reminders", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Reminder not found: \(identifier)",
            ])
        }
        try store.remove(reminder, commit: true)
    }

    private static func ensureAccess(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToReminders()
            guard granted else {
                throw NSError(domain: "Reminders", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Reminders permission denied",
                ])
            }
        default:
            throw NSError(domain: "Reminders", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Reminders permission required — open Settings",
            ])
        }
    }
}
