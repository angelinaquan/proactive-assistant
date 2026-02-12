import Foundation
import Observation
import OSLog

/// Persistent storage for ambient action items. JSON file in documents directory.
/// Saves are debounced to avoid performance issues during rapid mutations.
@MainActor
@Observable
final class AmbientStore {
    private let logger = Logger(subsystem: "ambient", category: "Store")
    private let fileManager = FileManager.default
    private(set) var items: [AmbientActionItem] = []
    private var saveTask: Task<Void, Never>?

    private var storeURL: URL {
        let docs = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ambient-actions.json")
    }

    init() { self.load() }

    func addItem(_ item: AmbientActionItem) { self.items.append(item); self.scheduleSave() }

    func updateItem(_ item: AmbientActionItem) {
        guard let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
        self.items[i] = item; self.scheduleSave()
    }

    func removeItem(id: String) { self.items.removeAll { $0.id == id }; self.scheduleSave() }
    func item(byId id: String) -> AmbientActionItem? { self.items.first { $0.id == id } }

    var executedItems: [AmbientActionItem] { self.items.filter { $0.executionStatus == .executed } }
    var suggestions: [AmbientActionItem] { self.items.filter { $0.executionStatus == .pending && !$0.autoExecute } }
    var pendingCount: Int {
        self.items.filter {
            $0.executionStatus == .executed || ($0.executionStatus == .pending && !$0.autoExecute)
        }.count
    }

    func deleteAllFromToday() {
        let cal = Calendar.current
        self.items.removeAll { cal.isDateInToday($0.detectedAt) }
        self.saveNow()
    }

    func deleteAll() {
        self.items.removeAll()
        self.saveNow()
    }

    func autoConfirmExpired() {
        var changed = false
        for i in self.items.indices where self.items[i].executionStatus == .executed && !self.items[i].canUndo {
            self.items[i].executionStatus = .confirmed
            self.items[i].confirmedAt = Date()
            changed = true
        }
        if changed { self.scheduleSave() }
    }

    // MARK: - Persistence (debounced)

    /// Schedule a save after a short delay. Multiple rapid mutations coalesce into one write.
    private func scheduleSave() {
        self.saveTask?.cancel()
        self.saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Write to disk immediately.
    private func saveNow() {
        self.saveTask?.cancel()
        self.saveTask = nil
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self.items).write(to: self.storeURL, options: .atomic)
        } catch {
            self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard self.fileManager.fileExists(atPath: self.storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: self.storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.items = try decoder.decode([AmbientActionItem].self, from: data)
        } catch {
            self.logger.error("Load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
