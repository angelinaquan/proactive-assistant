import Foundation
import OSLog

/// Tracks system identifiers of created items for undo operations.
@MainActor
final class RollbackStore {
    private let logger = Logger(subsystem: "ambient", category: "Rollback")
    private(set) var entries: [RollbackEntry] = []

    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ambient-rollback.json")
    }

    init() { self.load() }

    func recordExecution(actionPlanId: String, type: AmbientActionType, systemIdentifier: String?, undoWindowSeconds: Int = 1800) {
        self.entries.append(RollbackEntry(
            actionPlanId: actionPlanId, type: type, systemIdentifier: systemIdentifier,
            executedAt: Date(), undoExpiresAt: Date().addingTimeInterval(Double(undoWindowSeconds)), status: .executed))
        self.save()
    }

    func entry(forActionPlanId id: String) -> RollbackEntry? { self.entries.first { $0.actionPlanId == id } }

    func markUndone(actionPlanId: String) {
        guard let i = self.entries.firstIndex(where: { $0.actionPlanId == actionPlanId }) else { return }
        self.entries[i].status = .undone; self.save()
    }

    func markConfirmed(actionPlanId: String) {
        guard let i = self.entries.firstIndex(where: { $0.actionPlanId == actionPlanId }) else { return }
        self.entries[i].status = .confirmed; self.save()
    }

    func autoConfirmExpired() {
        let now = Date(); var changed = false
        for i in self.entries.indices where self.entries[i].status == .executed && self.entries[i].undoExpiresAt <= now {
            self.entries[i].status = .confirmed; changed = true
        }
        if changed { self.save() }
    }

    func removeEntry(actionPlanId: String) { self.entries.removeAll { $0.actionPlanId == actionPlanId }; self.save() }
    func removeAll() { self.entries.removeAll(); self.save() }

    /// Remove old confirmed/undone entries older than the given interval (default: 7 days).
    func cleanupOldEntries(olderThan interval: TimeInterval = 7 * 24 * 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        let before = self.entries.count
        self.entries.removeAll { entry in
            (entry.status == .confirmed || entry.status == .undone) && entry.executedAt < cutoff
        }
        if self.entries.count < before { self.save() }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: self.storeURL.path) else { return }
        do {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            self.entries = try d.decode([RollbackEntry].self, from: Data(contentsOf: self.storeURL))
        } catch { self.logger.error("Load failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func save() {
        do {
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            try e.encode(self.entries).write(to: self.storeURL, options: .atomic)
        } catch { self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)") }
    }
}

struct RollbackEntry: Codable, Identifiable, Sendable {
    let actionPlanId: String
    let type: AmbientActionType
    let systemIdentifier: String?
    let executedAt: Date
    let undoExpiresAt: Date
    var status: RollbackStatus
    var id: String { self.actionPlanId }
    var canUndo: Bool { self.status == .executed && Date() < self.undoExpiresAt }
    var undoTimeRemaining: TimeInterval { max(0, self.undoExpiresAt.timeIntervalSince(Date())) }
}

enum RollbackStatus: String, Codable, Sendable { case executed, confirmed, undone }
