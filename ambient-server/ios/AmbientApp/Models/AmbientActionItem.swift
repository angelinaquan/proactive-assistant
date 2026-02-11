import Foundation

/// Types of actions the ambient system can detect and execute.
enum AmbientActionType: String, Codable, Sendable {
    case reminder
    case calendarEvent = "calendar_event"
    case followUp = "follow_up"
    case commitment
    case note
    case draftMessage = "draft_message"
}

/// Lifecycle status of an action plan.
enum AmbientExecutionStatus: String, Codable, Sendable {
    case pending
    case executed
    case confirmed
    case undone
    case failed
}

/// Confidence classification.
enum AmbientConfidenceLevel: String, Codable, Sendable {
    case high
    case medium
    case low
}

/// An action plan received from the ambient intelligence server.
struct AmbientActionItem: Codable, Identifiable, Sendable {
    let id: String
    let type: AmbientActionType
    let confidence: Double
    let confidenceLevel: AmbientConfidenceLevel
    let autoExecute: Bool

    let sourceTranscript: String
    let contextWindow: String

    let actionDescription: String
    let actionParams: [String: AnyCodableValue]

    var executionStatus: AmbientExecutionStatus
    var executedAt: Date?
    var executionResult: [String: AnyCodableValue]?

    let detectedAt: Date
    var confirmedAt: Date?
    var undoneAt: Date?

    let people: [String]
    let deadline: String?

    let undoWindowSeconds: Int

    var canUndo: Bool {
        guard self.executionStatus == .executed else { return false }
        guard let executedAt else { return false }
        return Date().timeIntervalSince(executedAt) < Double(self.undoWindowSeconds)
    }

    var undoTimeRemaining: TimeInterval {
        guard let executedAt else { return 0 }
        return max(0, Double(self.undoWindowSeconds) - Date().timeIntervalSince(executedAt))
    }
}

/// A type-erased Codable value for flexible JSON dictionaries.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(v): try container.encode(v)
        case let .int(v): try container.encode(v)
        case let .double(v): try container.encode(v)
        case let .bool(v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? { if case let .string(v) = self { return v }; return nil }
    var boolValue: Bool? { if case let .bool(v) = self { return v }; return nil }
}
