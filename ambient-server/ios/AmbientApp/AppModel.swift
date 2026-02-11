import Foundation
import Observation
import SwiftUI

/// Central app model for the standalone Ambient Listening app.
/// No external framework dependencies.
@MainActor
@Observable
final class AppModel {
    let ambientStore = AmbientStore()
    let rollbackStore = RollbackStore()
    private(set) var proactiveExecutor: ProactiveExecutor!
    let ambientListening = AmbientListeningManager()

    var avatarImageURL: URL?

    init() {
        self.proactiveExecutor = ProactiveExecutor(
            rollbackStore: self.rollbackStore,
            ambientStore: self.ambientStore)

        // Load saved config
        let host = UserDefaults.standard.string(forKey: "ambient.serverHost") ?? ""
        let port = UserDefaults.standard.integer(forKey: "ambient.serverPort")
        let serverURL = Self.buildServerURL(host: host, port: port)

        self.ambientListening.configure(
            executor: self.proactiveExecutor,
            store: self.ambientStore,
            serverURL: serverURL)

        if UserDefaults.standard.bool(forKey: "ambient.enabled") {
            self.ambientListening.setEnabled(true)
        }
    }

    func updateServerConfig(host: String, port: Int) {
        let url = Self.buildServerURL(host: host, port: port)
        self.ambientListening.configure(
            executor: self.proactiveExecutor,
            store: self.ambientStore,
            serverURL: url)
    }

    private static func buildServerURL(host: String, port: Int) -> URL? {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }
        let p = port > 0 ? port : 8200
        return URL(string: "ws://\(h):\(p)/ws/ambient")
    }
}
