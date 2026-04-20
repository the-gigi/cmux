import Foundation

/// User-initiated action sent back through the transport to resolve a
/// pending item or jump to an agent's cmux terminal.
public enum WorkstreamAction: Sendable, Equatable {
    case approvePermission(itemId: UUID, mode: WorkstreamPermissionMode)
    case replyQuestion(itemId: UUID, selections: [String])
    case approveExitPlan(itemId: UUID, mode: WorkstreamExitPlanMode)
    case jumpToSession(workstreamId: String)
}
