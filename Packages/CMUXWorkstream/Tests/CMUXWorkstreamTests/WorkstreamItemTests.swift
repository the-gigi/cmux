import Foundation
import Testing
@testable import CMUXWorkstream

@Suite("WorkstreamItem")
struct WorkstreamItemTests {
    @Test("Actionable kinds default to pending, telemetry kinds to telemetry")
    func defaultStatusByKind() {
        let perm = WorkstreamItem(
            workstreamId: "claude-1",
            source: .claude,
            kind: .permissionRequest,
            payload: .permissionRequest(requestId: "r1", toolName: "Write", toolInputJSON: "{}", pattern: nil)
        )
        #expect(perm.status.isPending)

        let tool = WorkstreamItem(
            workstreamId: "claude-1",
            source: .claude,
            kind: .toolUse,
            payload: .toolUse(toolName: "Read", toolInputJSON: "{}")
        )
        if case .telemetry = tool.status {
            // ok
        } else {
            Issue.record("telemetry kind should default to .telemetry status")
        }
    }

    @Test("Codable round-trip preserves payload associated values")
    func codableRoundTrip() throws {
        let original = WorkstreamItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            workstreamId: "codex-42",
            source: .codex,
            kind: .permissionRequest,
            payload: .permissionRequest(
                requestId: "req-7",
                toolName: "shell",
                toolInputJSON: "{\"cmd\":\"rm -rf /\"}",
                pattern: "dangerous"
            )
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkstreamItem.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("WorkstreamKind.isActionable is correct")
    func isActionable() {
        #expect(WorkstreamKind.permissionRequest.isActionable)
        #expect(WorkstreamKind.exitPlan.isActionable)
        #expect(WorkstreamKind.question.isActionable)
        #expect(!WorkstreamKind.toolUse.isActionable)
        #expect(!WorkstreamKind.sessionStart.isActionable)
        #expect(!WorkstreamKind.todos.isActionable)
    }
}
