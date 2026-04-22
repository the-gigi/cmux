import XCTest
import CMUXWorkstream

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class FeedCoordinatorTests: XCTestCase {
    func testBlockingIngestExpiresItemWhenHookTimesOut() async {
        let store = WorkstreamStore(ringCapacity: 10)
        await MainActor.run {
            FeedCoordinator.shared.install(store: store)
        }

        let event = WorkstreamEvent(
            sessionId: "claude-timeout-test",
            hookEventName: .permissionRequest,
            source: "claude",
            cwd: "/tmp",
            toolName: "Bash",
            toolInputJSON: #"{"command":"true"}"#,
            requestId: "timeout-request"
        )

        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: FeedCoordinator.IngestBlockingResult?

        DispatchQueue.global(qos: .userInitiated).async {
            let ingestResult = FeedCoordinator.shared.ingestBlocking(
                event: event,
                waitTimeout: 0.05
            )
            lock.lock()
            result = ingestResult
            lock.unlock()
            done.signal()
        }

        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        lock.lock()
        let captured = result
        lock.unlock()

        guard case .timedOut = captured else {
            XCTFail("expected feed.push to time out")
            return
        }

        let status = await MainActor.run {
            store.items.first?.status
        }
        guard case .expired = status else {
            XCTFail("timed-out hook item should be expired")
            return
        }
    }
}
