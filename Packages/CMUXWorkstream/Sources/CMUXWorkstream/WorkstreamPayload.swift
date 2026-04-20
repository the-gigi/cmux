import Foundation

/// Inline permission decision modes the user can pick on a
/// `.permissionRequest` item. Wire format uses the lowercase raw values.
public enum WorkstreamPermissionMode: String, Codable, Sendable, Equatable, CaseIterable {
    case once
    case always
    case all
    case bypass
    case deny
}

/// Inline plan-mode decision the user can pick on an `.exitPlan` item.
public enum WorkstreamExitPlanMode: String, Codable, Sendable, Equatable, CaseIterable {
    case bypassPermissions
    case autoAccept
    case manual
    case deny
}

/// Single option on an `.question` item.
public struct WorkstreamQuestionOption: Codable, Sendable, Equatable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Task-list entry reported by Claude's `TodoWrite` tool or equivalent.
public struct WorkstreamTaskTodo: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable, Equatable {
        case pending
        case inProgress
        case completed
    }

    public let id: String
    public let content: String
    public let state: State

    public init(id: String, content: String, state: State) {
        self.id = id
        self.content = content
        self.state = state
    }
}

/// Kind-specific payload for a `WorkstreamItem`.
///
/// Associated-value enums are used so each kind only carries fields that
/// make sense for it; `Codable` synthesis works automatically in Swift 5.5+.
public enum WorkstreamPayload: Codable, Sendable, Equatable {
    case permissionRequest(
        requestId: String,
        toolName: String,
        toolInputJSON: String,
        pattern: String?
    )
    case exitPlan(
        requestId: String,
        plan: String,
        defaultMode: WorkstreamExitPlanMode
    )
    case question(
        requestId: String,
        prompt: String,
        options: [WorkstreamQuestionOption],
        multiSelect: Bool
    )
    case toolUse(toolName: String, toolInputJSON: String)
    case toolResult(toolName: String, resultJSON: String, isError: Bool)
    case userPrompt(text: String)
    case assistantMessage(text: String)
    case sessionStart
    case sessionEnd
    case stop(reason: String?)
    case todos([WorkstreamTaskTodo])
}
