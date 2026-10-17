import Foundation

enum DragOperation { case move, resize }

/// AX and CGEvent both use global coordinates with Y increasing downwards.
/// Keeping all calculations here avoids Cocoa's flipped screen coordinates.
struct DragGeometry {
    let frame: CGRect
    let anchor: CGPoint
    let operation: DragOperation
    var minimumSize = CGSize(width: 180, height: 120)

    var resizesLeft: Bool { anchor.x < frame.midX }
    var resizesTop: Bool { anchor.y < frame.midY }

    func frame(at point: CGPoint) -> CGRect {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        if operation == .move { return frame.offsetBy(dx: dx, dy: dy) }
        let width = max(minimumSize.width, frame.width + (resizesLeft ? -dx : dx))
        let height = max(minimumSize.height, frame.height + (resizesTop ? -dy : dy))
        return CGRect(x: resizesLeft ? frame.maxX - width : frame.minX,
                      y: resizesTop ? frame.maxY - height : frame.minY,
                      width: width, height: height)
    }

    /// Applications can impose a larger minimum or quantize their sizes.
    /// Re-anchor to the size AX actually accepted so the opposite corner stays put.
    func origin(forAcceptedSize size: CGSize) -> CGPoint {
        CGPoint(x: resizesLeft ? frame.maxX - size.width : frame.minX,
                y: resizesTop ? frame.maxY - size.height : frame.minY)
    }
}

/// A claimed button stays owned until its release, even if the modifier is
/// released first. Unrelated buttons retain their normal behavior.
struct DragOwnership {
    private(set) var button: Int?
    mutating func begin(button: Int) -> Bool {
        guard self.button == nil else { return false }
        self.button = button
        return true
    }
    func owns(button: Int) -> Bool { self.button == button }
    mutating func end(button: Int) -> Bool {
        guard owns(button: button) else { return false }
        self.button = nil
        return true
    }
}
