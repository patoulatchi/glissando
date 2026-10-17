import XCTest
import ApplicationServices
@testable import Glissando

final class WindowAccessTests: XCTestCase {
    func testAccessibilityWorkForOwnProcessRunsOnMainThread() {
        let finished = expectation(description: "Local AX work reaches main without blocking the worker")
        DispatchQueue.global().async {
            let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let wasMain = WindowAccess.onElementThread(element) { Thread.isMainThread }
            XCTAssertTrue(wasMain)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }

    func testAccessibilityWorkForOtherProcessesStaysOffMainThread() {
        let finished = expectation(description: "Remote AX work remains on worker")
        DispatchQueue.global().async {
            let element = AXUIElementCreateApplication(1)
            let wasMain = WindowAccess.onElementThread(element) { Thread.isMainThread }
            XCTAssertFalse(wasMain)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }

    func testMissingWindowSnapshotLetsInputPassThrough() {
        XCTAssertNil(WindowSnapshot().candidate(at: .zero))
    }
}
