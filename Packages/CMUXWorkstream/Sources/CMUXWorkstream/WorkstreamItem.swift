import Foundation

/// The user's decision on a resolved actionable item.
public enum WorkstreamDecision: Codable, Sendable, Equatable {
    case permission(WorkstreamPermissionMode)
    case exitPlan(WorkstreamExitPlanMode)
    case question(selections: [String])
}

/// Lifecycle state of a `WorkstreamItem`.
public enum WorkstreamStatus: Codable, Sendable, Equatable {
    /// Actionable item awaiting user input. Only valid for
    /// `.permissionRequest`, `.exitPlan`, `.question`.
    case pending
    /// Actionable item the user resolved with the given decision.
    case resolved(WorkstreamDecision, at: Date)
    /// Actionable item that timed out before the user acted.
    case expired(at: Date)
    /// Telemetry item (non-actionable). Always starts and stays here.
    case telemetry

    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

/// A single feed entry. Workstream IDs group items that belong to the same
/// agent session (e.g. `claude-<sessionId>`, `opencode-<sessionId>`).
public struct WorkstreamItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let workstreamId: String
    public let source: WorkstreamSource
    public let kind: WorkstreamKind
    public let createdAt: Date
    public var updatedAt: Date
    public var cwd: String?
    public var title: String?
    public var status: WorkstreamStatus
    public var payload: WorkstreamPayload

    public init(
        id: UUID = UUID(),
        workstreamId: String,
        source: WorkstreamSource,
        kind: WorkstreamKind,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        cwd: String? = nil,
        title: String? = nil,
        status: WorkstreamStatus? = nil,
        payload: WorkstreamPayload
    ) {
        self.id = id
        self.workstreamId = workstreamId
        self.source = source
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.cwd = cwd
        self.title = title
        self.status = status ?? (kind.isActionable ? .pending : .telemetry)
        self.payload = payload
    }
}
