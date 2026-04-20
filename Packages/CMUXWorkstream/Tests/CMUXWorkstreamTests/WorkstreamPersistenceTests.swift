import Foundation
import Testing
@testable import CMUXWorkstream

@Suite("WorkstreamPersistence")
struct WorkstreamPersistenceTests {
    @Test("Append + loadRecent round-trips items oldest-first")
    func appendAndLoad() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-workstream-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let persistence = WorkstreamPersistence(fileURL: tmp)
        let items = (0..<5).map { i in
            WorkstreamItem(
                workstreamId: "s\(i)",
                source: .claude,
                kind: .permissionRequest,
                payload: .permissionRequest(
                    requestId: "r\(i)",
                    toolName: "Write",
                    toolInputJSON: "{}",
                    pattern: nil
                )
            )
        }
        for item in items {
            try await persistence.append(item)
        }
        let loaded = try await persistence.loadRecent(limit: 10)
        #expect(loaded.count == 5)
        #expect(loaded.first?.workstreamId == "s0")
        #expect(loaded.last?.workstreamId == "s4")
    }

    @Test("loadRecent with limit returns the most recent suffix")
    func loadRecentLimit() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-workstream-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let persistence = WorkstreamPersistence(fileURL: tmp)
        for i in 0..<5 {
            try await persistence.append(WorkstreamItem(
                workstreamId: "s\(i)",
                source: .claude,
                kind: .permissionRequest,
                payload: .permissionRequest(requestId: "r\(i)", toolName: "t", toolInputJSON: "{}", pattern: nil)
            ))
        }
        let loaded = try await persistence.loadRecent(limit: 2)
        #expect(loaded.count == 2)
        #expect(loaded.first?.workstreamId == "s3")
        #expect(loaded.last?.workstreamId == "s4")
    }

    @Test("Missing file returns empty")
    func missingFileEmpty() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-workstream-missing-\(UUID().uuidString).jsonl")
        let persistence = WorkstreamPersistence(fileURL: tmp)
        let loaded = try await persistence.loadRecent(limit: 10)
        #expect(loaded.isEmpty)
    }

    @Test("clear removes the backing file")
    func clearRemovesFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-workstream-clear-\(UUID().uuidString).jsonl")
        let persistence = WorkstreamPersistence(fileURL: tmp)
        try await persistence.append(WorkstreamItem(
            workstreamId: "s", source: .claude, kind: .sessionStart, payload: .sessionStart
        ))
        #expect(FileManager.default.fileExists(atPath: tmp.path))
        try await persistence.clear()
        #expect(!FileManager.default.fileExists(atPath: tmp.path))
    }
}
