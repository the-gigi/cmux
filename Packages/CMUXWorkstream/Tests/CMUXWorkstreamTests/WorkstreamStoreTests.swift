import Foundation
import Testing
@testable import CMUXWorkstream

@MainActor
@Suite("WorkstreamStore")
struct WorkstreamStoreTests {
    @Test("ingest creates a pending item for permission requests")
    func ingestPending() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        #expect(store.items.count == 1)
        #expect(store.pending.count == 1)
        #expect(store.items[0].kind == .permissionRequest)
    }

    @Test("send(.approvePermission) marks the item resolved")
    func resolvePermission() async throws {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(.permission("s1", requestId: "r1"))
        let itemId = store.items[0].id
        try await store.send(.approvePermission(itemId: itemId, mode: .once))
        #expect(store.pending.isEmpty)
        if case .resolved(let decision, _) = store.items[0].status {
            #expect(decision == .permission(.once))
        } else {
            Issue.record("expected .resolved status")
        }
    }

    @Test("Ring buffer evicts oldest items past capacity")
    func ringEviction() {
        let store = WorkstreamStore(ringCapacity: 3)
        for i in 0..<5 {
            store.ingest(.permission("s\(i)", requestId: "r\(i)"))
        }
        #expect(store.items.count == 3)
        #expect(store.items.first?.workstreamId == "s2")
        #expect(store.items.last?.workstreamId == "s4")
    }

    @Test("expireAbandonedItems expires items whose agent PID is dead")
    func expireAbandoned() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })
        // Alive agent (pid=1000), dead agent (pid=2000).
        store.ingest(.permission("alive", requestId: "r1", at: clock.now, ppid: 1000))
        store.ingest(.permission("dead", requestId: "r2", at: clock.now, ppid: 2000))
        store.ingest(.permission("untracked", requestId: "r3", at: clock.now))
        // Injected liveness: only 1000 is alive.
        store.expireAbandonedItems { pid in pid == 1000 }
        #expect(store.items.count == 3)
        #expect(store.items[0].status.isPending)
        if case .expired = store.items[1].status {} else {
            Issue.record("dead-pid item should be expired")
        }
        // Item with no ppid: no change (we don't know liveness).
        #expect(store.items[2].status.isPending)
    }

    @Test("expirePending moves stale pending items to expired")
    func expirePending() {
        let clock = TestClock(initial: Date(timeIntervalSince1970: 0))
        let store = WorkstreamStore(ringCapacity: 10, clock: { clock.now })
        store.ingest(.permission("s1", requestId: "r1", at: clock.now))
        clock.advance(200)
        store.expirePending(olderThan: 60)
        if case .expired = store.items[0].status {
            // ok
        } else {
            Issue.record("expected .expired status after timeout")
        }
    }

    @Test("Telemetry items (toolUse) never enter pending")
    func telemetryNeverPending() {
        let store = WorkstreamStore(ringCapacity: 10)
        store.ingest(WorkstreamEvent(
            sessionId: "s1",
            hookEventName: .preToolUse,
            source: "claude",
            toolName: "Read"
        ))
        #expect(store.items.count == 1)
        #expect(store.pending.isEmpty)
        #expect(store.items[0].kind == .toolUse)
    }
}

/// Mutable clock wrapper safe to capture by a `@Sendable` closure in tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(initial: Date) { _now = initial }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }
}

private extension WorkstreamEvent {
    static func permission(
        _ sessionId: String,
        requestId: String,
        at date: Date = Date(),
        ppid: Int? = nil
    ) -> WorkstreamEvent {
        WorkstreamEvent(
            sessionId: sessionId,
            hookEventName: .permissionRequest,
            source: "claude",
            cwd: "/tmp",
            toolName: "Write",
            toolInputJSON: "{}",
            requestId: requestId,
            ppid: ppid,
            receivedAt: date
        )
    }
}
