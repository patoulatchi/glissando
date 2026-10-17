import AppKit
import OSLog

enum ModifierKey: String, CaseIterable {
    case option, control, command
    var title: String {
        switch self {
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

final class MouseListener {
    private let manipulator = WindowManipulator()
    private let snapshots = WindowSnapshot()
    private let logger = Logger(subsystem: "ch.nicolas.WindowDrag", category: "input")
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var starting = false
    private var failed = false
    private var active = false
    private var stopRequested = false
    private var enabledValue = true
    private var modifierValue = ModifierKey.option
    // Only touched on the event tap's thread.
    private var ownership = DragOwnership()
    private var cancelled = false
    private var escapeOwned = false
    var onError: ((String) -> Void)? {
        didSet { manipulator.onError = onError }
    }

    var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabledValue }
        set {
            lock.lock()
            enabledValue = newValue
            if newValue { failed = false }
            lock.unlock()
        }
    }
    var modifier: ModifierKey {
        get { lock.lock(); defer { lock.unlock() }; return modifierValue }
        set { lock.lock(); modifierValue = newValue; lock.unlock() }
    }
    var running: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    func startIfPermitted() {
        guard AXIsProcessTrusted() else { return }
        lock.lock()
        guard tap == nil, !starting, !failed, enabledValue else { lock.unlock(); return }
        starting = true
        stopRequested = false
        lock.unlock()
        snapshots.start()
        logger.info("Starting input listener")
        let thread = Thread { [weak self] in
            guard let self else { return }
            let events: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                .rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown, .keyUp]
            let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<MouseListener>.fromOpaque(context).takeUnretainedValue()
                return listener.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                self.lock.lock(); self.starting = false; self.failed = true; self.lock.unlock()
                self.logger.error("Event tap creation failed")
                DispatchQueue.main.async { self.snapshots.stop() }
                DispatchQueue.main.async { self.onError?("Mouse listener unavailable. Check Accessibility permission.") }
                return
            }
            let loop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.lock.lock()
            if self.stopRequested {
                self.starting = false
                self.lock.unlock()
                CFMachPortInvalidate(tap)
                return
            }
            self.tap = tap; self.runLoop = loop; self.active = true
            self.lock.unlock()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.lock.lock(); self.tap = nil; self.runLoop = nil; self.starting = false; self.active = false; self.lock.unlock()
            self.logger.info("Input listener stopped")
        }
        thread.name = "Glissando mouse listener"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        manipulator.cancel()
        snapshots.stop()
        lock.lock(); stopRequested = true; active = false; let loop = runLoop; lock.unlock()
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            manipulator.cancel()
            cancelled = true
            // Leave the tap disabled. The permission timer must not restart a
            // listener that macOS stopped for blocking input.
            lock.lock(); failed = true; active = false; lock.unlock()
            ownership = DragOwnership()
            escapeOwned = false
            logger.error("Input tap disabled by macOS (event type \(type.rawValue)); automatic restart blocked")
            DispatchQueue.main.async { [weak self] in
                self?.snapshots.stop()
                self?.onError?("Mouse listener stopped for safety. Toggle Enable Glissando off and on to retry.")
            }
            CFRunLoopStop(CFRunLoopGetCurrent())
            return false
        }
        if type == .keyUp, event.getIntegerValueField(.keyboardEventKeycode) == 53, escapeOwned {
            escapeOwned = false
            return true
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53,
           ownership.button != nil {
            manipulator.cancel()
            cancelled = true
            escapeOwned = true
            return true
        }
        let button: Int
        switch type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: button = 0
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp: button = 1
        default: return false
        }
        if ownership.owns(button: button) {
            if !enabled, !cancelled { manipulator.cancel(); cancelled = true }
            if type == .leftMouseUp || type == .rightMouseUp {
                if !cancelled { manipulator.end(at: event.location) }
                _ = ownership.end(button: button)
            } else if !cancelled {
                manipulator.update(to: event.location)
            }
            return true
        }
        guard type == .leftMouseDown || type == .rightMouseDown,
              enabled, ownership.button == nil else { return false }
        let modifiers: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand, .maskShift]
        guard event.flags.intersection(modifiers) == modifier.flag,
              let candidate = snapshots.candidate(at: event.location),
              ownership.begin(button: button) else { return false }
        cancelled = false
        manipulator.begin(candidate: candidate, at: event.location, operation: button == 0 ? .move : .resize)
        return true
    }
}
