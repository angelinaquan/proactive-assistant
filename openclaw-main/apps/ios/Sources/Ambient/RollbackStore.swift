import Foundation
import OSLog

/// Tracks the system identifiers of proactively created items so they can be
/// rolled back (deleted) when the user taps "Undo".
///
/// Each executed action stores the iOS system identifier (e.g., `calendarItemIdentifier`
/// or `eventIdentifier`) needed to delete the created reminder or calendar event.
@MainActor
final class RollbackStore {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "RollbackStore")
    private let fileManager = FileManager.default

    private(set) var entries: [RollbackEntry] = []

    private var storeURL: URL {
        let docs = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ambient-rollback.json")
    }

    init() {
        self.load()
    }

    // MARK: - Record

    /// Record that an action was executed and can be rolled back.
    func recordExecution(
        actionPlanId: String,
        type: AmbientActionType,
        systemIdentifier: String?,
        undoWindowSeconds: Int = 1800)
    {
        let entry = RollbackEntry(
            actionPlanId: actionPlanId,
            type: type,
            systemIdentifier: systemIdentifier,
            executedAt: Date(),
            undoExpiresAt: Date().addingTimeInterval(Double(undoWindowSeconds)),
            status: .executed)
        self.entries.append(entry)
        self.save()
        self.logger.info(
            "Recorded rollback entry: \(actionPlanId) type=\(type.rawValue, privacy: .public) sysId=\(systemIdentifier ?? "nil", privacy: .public)")
    }

    // MARK: - Lookup

    func entry(forActionPlanId id: String) -> RollbackEntry? {
        self.entries.first { $0.actionPlanId == id }
    }

    /// Entries that can still be undone (within undo window).
    var undoableEntries: [RollbackEntry] {
        let now = Date()
        return self.entries.filter { $0.status == .executed && $0.undoExpiresAt > now }
    }

    // MARK: - Update

    func markUndone(actionPlanId: String) {
        guard let index = self.entries.firstIndex(where: { $0.actionPlanId == actionPlanId }) else {
            return
        }
        self.entries[index].status = .undone
        self.save()
    }

    func markConfirmed(actionPlanId: String) {
        guard let index = self.entries.firstIndex(where: { $0.actionPlanId == actionPlanId }) else {
            return
        }
        self.entries[index].status = .confirmed
        self.save()
    }

    /// Auto-confirm entries whose undo window has expired.
    func autoConfirmExpired() {
        let now = Date()
        var changed = false
        for i in self.entries.indices {
            if self.entries[i].status == .executed, self.entries[i].undoExpiresAt <= now {
                self.entries[i].status = .confirmed
                changed = true
            }
        }
        if changed { self.save() }
    }

    // MARK: - Cleanup

    func removeEntry(actionPlanId: String) {
        self.entries.removeAll { $0.actionPlanId == actionPlanId }
        self.save()
    }

    func removeAll() {
        self.entries.removeAll()
        self.save()
    }

    // MARK: - Persistence

    private func load() {
        guard self.fileManager.fileExists(atPath: self.storeURL.path) else {
            self.entries = []
            return
        }
        do {
            let data = try Data(contentsOf: self.storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.entries = try decoder.decode([RollbackEntry].self, from: data)
        } catch {
            self.logger.error("Failed to load rollback store: \(error.localizedDescription, privacy: .public)")
            self.entries = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(self.entries)
            try data.write(to: self.storeURL, options: .atomic)
        } catch {
            self.logger.error("Failed to save rollback store: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - RollbackEntry

struct RollbackEntry: Codable, Identifiable, Sendable {
    let actionPlanId: String
    let type: AmbientActionType
    let systemIdentifier: String?
    let executedAt: Date
    let undoExpiresAt: Date
    var status: RollbackStatus

    var id: String { self.actionPlanId }

    var canUndo: Bool {
        self.status == .executed && Date() < self.undoExpiresAt
    }

    var undoTimeRemaining: TimeInterval {
        max(0, self.undoExpiresAt.timeIntervalSince(Date()))
    }
}

enum RollbackStatus: String, Codable, Sendable {
    case executed
    case confirmed
    case undone
}
