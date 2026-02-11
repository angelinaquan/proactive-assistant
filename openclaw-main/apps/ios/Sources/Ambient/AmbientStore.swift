import Foundation
import OSLog

/// Persistent storage for ambient action items and transcript history.
///
/// Uses a JSON file in the app's documents directory. All mutations are
/// atomic (write-to-temp then rename) to prevent corruption.
@MainActor
final class AmbientStore {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "AmbientStore")
    private let fileManager = FileManager.default

    private(set) var items: [AmbientActionItem] = []

    private var storeURL: URL {
        let docs = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ambient-actions.json")
    }

    init() {
        self.load()
    }

    // MARK: - CRUD

    func addItem(_ item: AmbientActionItem) {
        self.items.append(item)
        self.save()
    }

    func updateItem(_ item: AmbientActionItem) {
        guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
        self.items[index] = item
        self.save()
    }

    func removeItem(id: String) {
        self.items.removeAll { $0.id == id }
        self.save()
    }

    func item(byId id: String) -> AmbientActionItem? {
        self.items.first { $0.id == id }
    }

    // MARK: - Queries

    /// Items that were auto-executed and are awaiting confirmation or undo.
    var executedItems: [AmbientActionItem] {
        self.items.filter { $0.executionStatus == .executed }
    }

    /// Items that are suggestions (not auto-executed).
    var suggestions: [AmbientActionItem] {
        self.items.filter { $0.executionStatus == .pending && !$0.autoExecute }
    }

    /// Items confirmed by user or auto-confirmed after undo window.
    var confirmedItems: [AmbientActionItem] {
        self.items.filter { $0.executionStatus == .confirmed }
    }

    /// All items from today.
    var todayItems: [AmbientActionItem] {
        let calendar = Calendar.current
        return self.items.filter { calendar.isDateInToday($0.detectedAt) }
    }

    /// Number of items needing attention (executed but not confirmed, or suggestions).
    var pendingCount: Int {
        self.items.filter {
            $0.executionStatus == .executed || ($0.executionStatus == .pending && !$0.autoExecute)
        }.count
    }

    // MARK: - Bulk operations

    func deleteAllFromToday() {
        let calendar = Calendar.current
        self.items.removeAll { calendar.isDateInToday($0.detectedAt) }
        self.save()
    }

    func deleteAll() {
        self.items.removeAll()
        self.save()
    }

    /// Auto-confirm items whose undo window has expired.
    func autoConfirmExpired() {
        var changed = false
        for i in self.items.indices {
            if self.items[i].executionStatus == .executed, !self.items[i].canUndo {
                self.items[i].executionStatus = .confirmed
                self.items[i].confirmedAt = Date()
                changed = true
            }
        }
        if changed {
            self.save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard self.fileManager.fileExists(atPath: self.storeURL.path) else {
            self.items = []
            return
        }
        do {
            let data = try Data(contentsOf: self.storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.items = try decoder.decode([AmbientActionItem].self, from: data)
            self.logger.info("Loaded \(self.items.count) ambient items")
        } catch {
            self.logger.error("Failed to load ambient store: \(error.localizedDescription, privacy: .public)")
            self.items = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self.items)

            // Atomic write: temp file then rename
            let tmpURL = self.storeURL.deletingLastPathComponent()
                .appendingPathComponent("ambient-actions.tmp.\(Date().timeIntervalSince1970).json")
            try data.write(to: tmpURL, options: .atomic)
            _ = try? self.fileManager.replaceItemAt(self.storeURL, withItemAt: tmpURL)
            try? self.fileManager.removeItem(at: tmpURL)
        } catch {
            self.logger.error("Failed to save ambient store: \(error.localizedDescription, privacy: .public)")
        }
    }
}
