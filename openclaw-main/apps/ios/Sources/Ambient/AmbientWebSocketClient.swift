import Foundation
import OSLog

/// WebSocket client for connecting to the ambient intelligence server.
///
/// Sends PCM audio chunks and JSON control messages, receives transcript
/// segments and action plans from the server.
@MainActor
final class AmbientWebSocketClient {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "AmbientWS")

    var onTranscript: ((String, Bool) -> Void)?
    var onActionPlan: ((AmbientActionItem) -> Void)?
    var onError: ((String) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false
    private var serverURL: URL?

    // MARK: - Connection

    func connect(to url: URL) {
        self.disconnect()
        self.serverURL = url
        self.session = URLSession(configuration: .default)
        self.webSocketTask = self.session?.webSocketTask(with: url)
        self.webSocketTask?.resume()
        self.isConnected = true
        self.onConnectionStateChanged?(true)
        self.logger.info("Connecting to ambient server: \(url.absoluteString, privacy: .public)")
        self.receiveLoop()
    }

    func disconnect() {
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        if self.isConnected {
            self.isConnected = false
            self.onConnectionStateChanged?(false)
        }
    }

    // MARK: - Send

    /// Send a PCM audio chunk to the server.
    func sendAudioChunk(_ data: Data) {
        guard self.isConnected else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        self.webSocketTask?.send(message) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.logger.error("Send audio failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Send a pause command to the server.
    func sendPause() {
        self.sendJSON(["type": "pause"])
    }

    /// Send a resume command to the server.
    func sendResume() {
        self.sendJSON(["type": "resume"])
    }

    /// Send feedback on an action plan.
    func sendFeedback(actionPlanId: String, action: String, editedParams: [String: Any]? = nil) {
        var payload: [String: Any] = [
            "action_plan_id": actionPlanId,
            "action": action,
        ]
        if let editedParams {
            payload["edited_params"] = editedParams
        }
        self.sendJSON(["type": "feedback", "payload": payload])
    }

    // MARK: - Private

    private func sendJSON(_ dict: [String: Any]) {
        guard self.isConnected else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let message = URLSessionWebSocketTask.Message.string(text)
            self.webSocketTask?.send(message) { [weak self] error in
                if let error {
                    Task { @MainActor in
                        self?.logger.error("Send JSON failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch {
            self.logger.error("JSON encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receiveLoop() {
        self.webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(message):
                    self.handleMessage(message)
                    self.receiveLoop()
                case let .failure(error):
                    self.logger.error("WS receive error: \(error.localizedDescription, privacy: .public)")
                    self.isConnected = false
                    self.onConnectionStateChanged?(false)
                    // Attempt reconnect after delay
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard let self else { return }
                        if let url = self.serverURL {
                            self.connect(to: url)
                        }
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case let .string(text):
            self.parseServerMessage(text)
        case let .data(data):
            if let text = String(data: data, encoding: .utf8) {
                self.parseServerMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let msgType = json["type"] as? String ?? ""
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch msgType {
        case "transcript":
            let transcriptText = payload["text"] as? String ?? ""
            let isPartial = payload["is_partial"] as? Bool ?? true
            if !transcriptText.isEmpty {
                self.onTranscript?(transcriptText, isPartial)
            }

        case "action_plan":
            if let item = self.parseActionPlan(payload) {
                self.onActionPlan?(item)
            }

        case "error":
            let message = payload["message"] as? String ?? "Unknown error"
            self.onError?(message)

        default:
            break
        }
    }

    private func parseActionPlan(_ payload: [String: Any]) -> AmbientActionItem? {
        // Re-encode to JSON data and decode with Codable
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AmbientActionItem.self, from: data)
        } catch {
            self.logger.error("Failed to parse action plan: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
