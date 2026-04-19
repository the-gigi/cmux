import XCTest
import SwiftUI

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class SessionIndexViewTests: XCTestCase {
    func testSectionPopoverHostCoordinatorSkipsHiddenRefreshes() {
        var isPresented = false
        let binding = Binding(
            get: { isPresented },
            set: { isPresented = $0 }
        )
        let section = IndexSection(
            key: .directory("/tmp"),
            title: "tmp",
            icon: .folder,
            entries: []
        )
        let host = SectionPopoverHost(
            isPresented: binding,
            section: section,
            search: { _, _, _, _ in
                SessionIndexStore.SearchOutcome(entries: [], errors: [])
            },
            loadSnapshot: { cwd in
                DirectorySnapshot(cwd: cwd ?? "", entries: [], errors: [])
            },
            onResume: nil
        )
        let coordinator = host.makeCoordinator()

        coordinator.update(
            section: section,
            search: { _, _, _, _ in
                SessionIndexStore.SearchOutcome(entries: [], errors: [])
            },
            loadSnapshot: { cwd in
                DirectorySnapshot(cwd: cwd ?? "", entries: [], errors: [])
            },
            onResume: nil
        )
        coordinator.update(
            section: section,
            search: { _, _, _, _ in
                SessionIndexStore.SearchOutcome(entries: [], errors: [])
            },
            loadSnapshot: { cwd in
                DirectorySnapshot(cwd: cwd ?? "", entries: [], errors: [])
            },
            onResume: nil
        )

        XCTAssertEqual(coordinator.debugRefreshContentCallCount, 0)
    }
}
