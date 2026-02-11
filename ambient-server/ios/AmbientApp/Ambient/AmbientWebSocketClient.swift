import Foundation
import OSLog

/// WebSocket client for the ambient intelligence server.
/// Sends PCM audio chunks (thread-safe), receives transcripts and action plans.
@MainActor
final class AmbientWebSocketClient {
    private let logger = Logger(subsystem: "ambient", category: "WS")

    var onTranscript: ((String, Bool) -> Void)?
    var onActionPlan: ((AmbientActionItem) -> Void)?
    var onError: ((String) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false
    private var serverURL: URL?
    private let audioSendTask = WebSocketTaskRef()

    func connect(to url: URL) {
        self.disconnect()
        self.serverURL = url
        self.session = URLSession(configuration: .default)
        self.webSocketTask = self.session?.webSocketTask(with: url)
        self.webSocketTask?.resume()
        self.audioSendTask.set(self.webSocketTask)
        self.isConnected = true
        self.onConnectionStateChanged?(true)
        self.receiveLoop()
    }

    func disconnect() {
        self.audioSendTask.set(nil)
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        if self.isConnected { self.isConnected = false; self.onConnectionStateChanged?(false) }
    }

    /// Thread-safe audio sending from the real-time audio thread.
    nonisolated func sendAudioChunk(_ data: Data) {
        self.audioSendTask.send(.data(data))
    }

    func sendPause() { self.sendJSON(["type": "pause"]) }
    func sendResume() { self.sendJSON(["type": "resume"]) }

    func sendFeedback(actionPlanId: String, action: String) {
        self.sendJSON(["type": "feedback", "payload": ["action_plan_id": actionPlanId, "action": action]])
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard self.isConnected, let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        self.webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveLoop() {
        self.webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(msg): self.handleMessage(msg); self.receiveLoop()
                case .failure:
                    self.isConnected = false; self.onConnectionStateChanged?(false)
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard let self, let url = self.serverURL else { return }
                        self.connect(to: url)
                    }
                }
            }
        }
    }

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) {
        let text: String
        switch msg {
        case let .string(t): text = t
        case let .data(d): text = String(data: d, encoding: .utf8) ?? ""; if text.isEmpty { return }
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = json["type"] as? String ?? ""
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch type {
        case "transcript":
            let t = payload["text"] as? String ?? ""
            if !t.isEmpty { self.onTranscript?(t, payload["is_partial"] as? Bool ?? true) }
        case "action_plan":
            if let d = try? JSONSerialization.data(withJSONObject: payload) {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601; dec.keyDecodingStrategy = .convertFromSnakeCase
                if let item = try? dec.decode(AmbientActionItem.self, from: d) { self.onActionPlan?(item) }
            }
        case "error":
            self.onError?(payload["message"] as? String ?? "Unknown error")
        default: break
        }
    }
}

/// Thread-safe WebSocket task reference for audio sending from audio thread.
private final class WebSocketTaskRef: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    func set(_ task: URLSessionWebSocketTask?) { self.lock.lock(); self.task = task; self.lock.unlock() }
    func send(_ msg: URLSessionWebSocketTask.Message) {
        self.lock.lock(); let t = self.task; self.lock.unlock(); t?.send(msg) { _ in }
    }
}
