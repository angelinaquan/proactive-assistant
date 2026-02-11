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
    case high   // >= 0.8 → auto-execute
    case medium // 0.5–0.8 → suggestion
    case low    // < 0.5 → discard
}

/// An action plan received from the ambient intelligence server.
///
/// High-confidence plans (`autoExecute == true`) are immediately executed
/// by the `ProactiveExecutor`. Lower-confidence plans are surfaced as
/// suggestions in the review timeline.
struct AmbientActionItem: Codable, Identifiable, Sendable {
    let id: String
    let type: AmbientActionType
    let confidence: Double
    let confidenceLevel: AmbientConfidenceLevel
    let autoExecute: Bool

    // What was heard
    let sourceTranscript: String
    let contextWindow: String

    // What the system decided to do
    let actionDescription: String
    let actionParams: [String: AnyCodableValue]

    // Execution state
    var executionStatus: AmbientExecutionStatus
    var executedAt: Date?
    var executionResult: [String: AnyCodableValue]?

    // Timestamps
    let detectedAt: Date
    var confirmedAt: Date?
    var undoneAt: Date?

    // Entities
    let people: [String]
    let deadline: String?

    // Undo window (seconds)
    let undoWindowSeconds: Int

    /// Whether the undo window is still open.
    var canUndo: Bool {
        guard self.executionStatus == .executed else { return false }
        guard let executedAt else { return false }
        let elapsed = Date().timeIntervalSince(executedAt)
        return elapsed < Double(self.undoWindowSeconds)
    }

    /// Time remaining in the undo window, in seconds.
    var undoTimeRemaining: TimeInterval {
        guard let executedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(executedAt)
        return max(0, Double(self.undoWindowSeconds) - elapsed)
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
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case let .int(v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case let .double(v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }
}
