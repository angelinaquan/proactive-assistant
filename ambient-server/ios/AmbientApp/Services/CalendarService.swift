import EventKit
import Foundation

/// Standalone calendar service — creates and deletes events using EventKit.
/// No external framework dependencies.
final class CalendarService: Sendable {

    func add(
        title: String,
        startISO: String,
        endISO: String,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil
    ) async throws -> String {
        let store = EKEventStore()
        try await Self.ensureAccess(store: store)

        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: startISO) else {
            throw NSError(domain: "Calendar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid startISO: \(startISO)",
            ])
        }
        guard let end = formatter.date(from: endISO) else {
            throw NSError(domain: "Calendar", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid endISO: \(endISO)",
            ])
        }

        let event = EKEvent(eventStore: store)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            event.location = location
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            event.notes = notes
        }
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier ?? ""
    }

    func delete(identifier: String) async throws {
        let store = EKEventStore()
        try await Self.ensureAccess(store: store)

        guard let event = store.event(withIdentifier: identifier) else {
            throw NSError(domain: "Calendar", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Event not found: \(identifier)",
            ])
        }
        try store.remove(event, span: .thisEvent)
    }

    private static func ensureAccess(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                throw NSError(domain: "Calendar", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Calendar permission denied",
                ])
            }
        default:
            throw NSError(domain: "Calendar", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Calendar permission required — open Settings",
            ])
        }
    }
}
