import Foundation
import OSLog

/// REST client for the /chat endpoint. Sends user messages, receives AI responses.
actor ChatClient {
    private let logger = Logger(subsystem: "ambient", category: "ChatClient")
    private let session = URLSession(configuration: .default)
    private let sessionId: String

    init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
    }

    /// Send a user message and get an AI response.
    func send(message: String, serverBaseURL: URL) async throws -> String {
        let chatURL = serverBaseURL.appendingPathComponent("chat")

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "message": message,
            "session_id": self.sessionId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ChatClientError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["reply"] as? String
        else {
            throw ChatClientError.invalidJSON
        }

        self.logger.info("Chat reply: \(reply.prefix(80), privacy: .public)...")
        return reply
    }
}

enum ChatClientError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case let .serverError(code): return "Server error: \(code)"
        case .invalidJSON: return "Could not parse server response"
        }
    }
}
