import AppKit
import ApplicationServices
import OSLog

struct WindowCandidate {
    let pid: pid_t
    let bounds: CGRect
}

enum WindowAccess {
    /// Called only on the snapshot worker, never from an input callback.
    static func candidates() -> [WindowCandidate] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.1,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw),
                  bounds.width > 60, bounds.height > 40,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            return WindowCandidate(pid: pid, bounds: bounds)
        }
    }

    // AX calls targeting this process execute AppKit code directly. They must
    // run on main, even though remote applications are accessed on a worker.
    static func onElementThread<T>(_ element: AXUIElement, _ body: () -> T) -> T {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier && !Thread.isMainThread {
            return DispatchQueue.main.sync(execute: body)
        }
        return body()
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        onElementThread(element) {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
    }

    static func position(_ window: AXUIElement) -> CGPoint? {
        guard let raw = attribute(window, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(raw as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ window: AXUIElement) -> CGSize? {
        guard let raw = attribute(window, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(raw as! AXValue, .cgSize, &size) ? size : nil
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = position(window), let size = size(window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) {
            _ = onElementThread(window) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    @discardableResult static func setSize(_ size: CGSize, of window: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return onElementThread(window) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    static func isSettable(_ name: String, on window: AXUIElement) -> Bool {
        onElementThread(window) {
            var result = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(window, name as CFString, &result) == .success && result.boolValue
        }
    }

    static func resolve(_ candidate: WindowCandidate, at point: CGPoint) -> AXUIElement? {
        if candidate.pid == ProcessInfo.processInfo.processIdentifier && !Thread.isMainThread {
            return DispatchQueue.main.sync { resolve(candidate, at: point) }
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
           let hit {
            var pid: pid_t = 0
            AXUIElementGetPid(hit, &pid)
            if pid == candidate.pid {
                if attribute(hit, kAXRoleAttribute) as? String == kAXWindowRole { return hit }
                if let raw = attribute(hit, kAXWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
                    return (raw as! AXUIElement)
                }
            }
        }
        // Some apps expose a window but no accessible descendant under the
        // pointer. Match the window-server frame instead of using the focused
        // window, which could belong to a different document or display.
        let app = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for window in windows.prefix(32) {
            AXUIElementSetMessagingTimeout(window, 0.15)
            guard let frame = frame(window) else { continue }
            if abs(frame.minX - candidate.bounds.minX) < 6,
               abs(frame.minY - candidate.bounds.minY) < 6,
               abs(frame.width - candidate.bounds.width) < 6,
               abs(frame.height - candidate.bounds.height) < 6 { return window }
        }
        return nil
    }
}

final class WindowManipulator {
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "Glissando.window-access", qos: .userInteractive)
    private let lock = NSLock()
    private var pendingPoint: CGPoint?
    private var updateScheduled = false
    private var session: (window: AXUIElement, geometry: DragGeometry)?

    func begin(candidate: WindowCandidate, at point: CGPoint, operation: DragOperation) {
        queue.async { [weak self] in
            guard let self else { return }
            self.session = nil
            guard let window = WindowAccess.resolve(candidate, at: point) else {
                return self.report("This window does not expose Accessibility controls.")
            }
            AXUIElementSetMessagingTimeout(window, 0.15)
            guard WindowAccess.attribute(window, "AXFullScreen") as? Bool != true,
                  let frame = WindowAccess.frame(window),
                  WindowAccess.isSettable(kAXPositionAttribute, on: window),
                  operation == .move || WindowAccess.isSettable(kAXSizeAttribute, on: window) else {
                return self.report("This window cannot be moved or resized in its current state.")
            }
            self.session = (window, DragGeometry(frame: frame, anchor: point, operation: operation))
        }
    }

    func update(to point: CGPoint) {
        lock.lock()
        pendingPoint = point
        let schedule = !updateScheduled
        updateScheduled = true
        lock.unlock()
        guard schedule else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let point = self.pendingPoint
            self.pendingPoint = nil
            self.updateScheduled = false
            self.lock.unlock()
            if let point { self.apply(point) }
        }
    }

    func end(at point: CGPoint) {
        queue.async { [weak self] in
            self?.apply(point)
            self?.session = nil
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self, let session = self.session else { return }
            WindowAccess.setSize(session.geometry.frame.size, of: session.window)
            WindowAccess.setPosition(session.geometry.frame.origin, of: session.window)
            self.session = nil
        }
    }

    private func apply(_ point: CGPoint) {
        guard let session else { return }
        let desired = session.geometry.frame(at: point)
        if session.geometry.operation == .move {
            WindowAccess.setPosition(desired.origin, of: session.window)
        } else if WindowAccess.setSize(desired.size, of: session.window) == .success {
            let accepted = WindowAccess.size(session.window) ?? desired.size
            WindowAccess.setPosition(session.geometry.origin(forAcceptedSize: accepted), of: session.window)
        }
    }

    private func report(_ message: String) {
        Logger(subsystem: "ch.nicolas.WindowDrag", category: "windows").error("\(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}

/// Input callbacks only read a recent snapshot. A busy WindowServer cannot
/// block input delivery; missing, busy or stale snapshots let the click pass.
final class WindowSnapshot {
    private let lock = NSLock()
    private var windows: [WindowCandidate] = []
    private var timestamp: TimeInterval = 0
    private var timer: DispatchSourceTimer?

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "Glissando.window-snapshot", qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let windows = WindowAccess.candidates()
            self.lock.lock()
            self.windows = windows
            self.timestamp = ProcessInfo.processInfo.systemUptime
            self.lock.unlock()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    func candidate(at point: CGPoint) -> WindowCandidate? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - timestamp < 0.3 else { return nil }
        return windows.first { $0.bounds.contains(point) }
    }
}
