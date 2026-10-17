import XCTest
@testable import Glissando

final class DragGeometryTests: XCTestCase {
    let frame = CGRect(x: -800, y: 120, width: 600, height: 400)

    func testMovingAcrossDisplaysUsesGlobalCoordinates() {
        let drag = DragGeometry(frame: frame, anchor: CGPoint(x: -500, y: 300), operation: .move)
        XCTAssertEqual(drag.frame(at: CGPoint(x: 200, y: -50)),
                       CGRect(x: -100, y: -230, width: 600, height: 400))
    }

    func testAllFourResizeCornersKeepTheOppositeCornerFixed() {
        for left in [false, true] {
            for top in [false, true] {
                let anchor = CGPoint(x: left ? frame.minX + 10 : frame.maxX - 10,
                                     y: top ? frame.minY + 10 : frame.maxY - 10)
                let drag = DragGeometry(frame: frame, anchor: anchor, operation: .resize)
                let resized = drag.frame(at: CGPoint(x: anchor.x + (left ? -80 : 80),
                                                     y: anchor.y + (top ? -60 : 60)))
                XCTAssertEqual(resized.size, CGSize(width: 680, height: 460))
                XCTAssertEqual(left ? resized.maxX : resized.minX, left ? frame.maxX : frame.minX)
                XCTAssertEqual(top ? resized.maxY : resized.minY, top ? frame.maxY : frame.minY)
            }
        }
    }

    func testDraggingPastTheOppositeCornerClampsWithoutFlipping() {
        let drag = DragGeometry(frame: frame, anchor: frame.origin, operation: .resize)
        let resized = drag.frame(at: CGPoint(x: frame.maxX + 100, y: frame.maxY + 100))
        XCTAssertEqual(resized.size, CGSize(width: 180, height: 120))
        XCTAssertEqual(resized.maxX, frame.maxX)
        XCTAssertEqual(resized.maxY, frame.maxY)
    }

    func testApplicationMinimumSizeDoesNotShiftTheFixedCorner() {
        let drag = DragGeometry(frame: frame, anchor: frame.origin, operation: .resize)
        let actualSize = CGSize(width: 420, height: 260)
        let origin = drag.origin(forAcceptedSize: actualSize)
        XCTAssertEqual(origin.x + actualSize.width, frame.maxX)
        XCTAssertEqual(origin.y + actualSize.height, frame.maxY)
    }

    func testUnrelatedReleaseDoesNotEndOrLeakAnOwnedDrag() {
        var ownership = DragOwnership()
        XCTAssertTrue(ownership.begin(button: 0))
        XCTAssertFalse(ownership.begin(button: 1))
        XCTAssertFalse(ownership.end(button: 1))
        XCTAssertTrue(ownership.owns(button: 0))
        XCTAssertTrue(ownership.end(button: 0))
        XCTAssertFalse(ownership.end(button: 0))
        XCTAssertTrue(ownership.begin(button: 1))
    }
}
