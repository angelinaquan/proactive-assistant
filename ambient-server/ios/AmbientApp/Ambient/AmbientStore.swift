import Foundation
import OSLog

/// Persistent storage for ambient action items. JSON file in documents directory.
@MainActor
final class AmbientStore: Observable {
    private let logger = Logger(subsystem: "ambient", category: "Store")
    private let fileManager = FileManager.default
    private(set) var items: [AmbientActionItem] = []

    private var storeURL: URL {
        let docs = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ambient-actions.json")
    }

    init() { self.load() }

    func addItem(_ item: AmbientActionItem) { self.items.append(item); self.save() }

    func updateItem(_ item: AmbientActionItem) {
        guard let i = self.items.firstIndex(where: { $0.id == item.id }) else { return }
        self.items[i] = item; self.save()
    }

    func removeItem(id: String) { self.items.removeAll { $0.id == id }; self.save() }
    func item(byId id: String) -> AmbientActionItem? { self.items.first { $0.id == id } }

    var executedItems: [AmbientActionItem] { self.items.filter { $0.executionStatus == .executed } }
    var suggestions: [AmbientActionItem] { self.items.filter { $0.executionStatus == .pending && !$0.autoExecute } }
    var pendingCount: Int { self.items.filter { $0.executionStatus == .executed || ($0.executionStatus == .pending && !$0.autoExecute) }.count }

    func deleteAllFromToday() {
        let cal = Calendar.current; self.items.removeAll { cal.isDateInToday($0.detectedAt) }; self.save()
    }

    func deleteAll() { self.items.removeAll(); self.save() }

    func autoConfirmExpired() {
        var changed = false
        for i in self.items.indices where self.items[i].executionStatus == .executed && !self.items[i].canUndo {
            self.items[i].executionStatus = .confirmed; self.items[i].confirmedAt = Date(); changed = true
        }
        if changed { self.save() }
    }

    private func load() {
        guard self.fileManager.fileExists(atPath: self.storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: self.storeURL)
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            self.items = try d.decode([AmbientActionItem].self, from: data)
        } catch { self.logger.error("Load failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func save() {
        do {
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try e.encode(self.items).write(to: self.storeURL, options: .atomic)
        } catch { self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)") }
    }
}
