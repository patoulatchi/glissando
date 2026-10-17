import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let listener = MouseListener()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var guideWindow: NSWindow?
    private var testWindow: NSWindow?
    private var guideStatus: NSTextField?
    private var guideMove: NSTextField?
    private var guideResize: NSTextField?
    private var frameLabel: NSTextField?
    private var testInstructions: NSTextField?
    private var lastError: String?
    private var modifier: ModifierKey {
        get { ModifierKey(rawValue: UserDefaults.standard.string(forKey: "modifier") ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "modifier"); listener.modifier = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second open should reveal the existing guide, not install another tap.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApp.terminate(nil)
            return
        }
        listener.modifier = modifier
        listener.enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        listener.onError = { [weak self] error in self?.lastError = error }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Glissando")
        statusItem.button?.toolTip = "Glissando — move and resize windows"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        if !AXIsProcessTrusted() || !UserDefaults.standard.bool(forKey: "guideShown") { showGuide(nil) }
        UserDefaults.standard.set(true, forKey: "guideShown")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showGuide(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        listener.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = !AXIsProcessTrusted() ? "Accessibility access required"
            : !listener.enabled ? "Paused" : listener.running ? "Ready" : "Starting mouse listener…"
        menu.addItem(NSMenuItem(title: state, action: nil, keyEquivalent: ""))
        if let lastError { menu.addItem(NSMenuItem(title: lastError, action: nil, keyEquivalent: "")) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "\(modifier.title) + left drag: move", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(modifier.title) + right drag: resize", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Esc during a drag: restore", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let enabled = item("Enable Glissando", #selector(toggleEnabled(_:)))
        enabled.state = listener.enabled ? .on : .off
        menu.addItem(enabled)
        let keys = NSMenuItem(title: "Modifier Key", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for key in ModifierKey.allCases {
            let choice = item(key.title, #selector(changeModifier(_:)))
            choice.representedObject = key.rawValue
            choice.state = key == modifier ? .on : .off
            submenu.addItem(choice)
        }
        keys.submenu = submenu
        menu.addItem(keys)
        menu.addItem(.separator())
        menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibility(_:))))
        menu.addItem(item("How to Use…", #selector(showGuide(_:))))
        menu.addItem(item("Open Test Window", #selector(showTestWindow(_:))))
        menu.addItem(.separator())
        let quit = item("Quit Glissando", #selector(quit(_:)))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted { listener.startIfPermitted() }
        else if listener.running { listener.stop() }
        guideStatus?.stringValue = !trusted ? "Accessibility access is required to control windows."
            : !listener.enabled ? "Glissando is paused. Enable it from the menu bar."
            : listener.running ? "Ready. Try the gestures on any movable window."
            : "Starting the mouse listener…"
        guideStatus?.textColor = trusted ? .secondaryLabelColor : .labelColor
        statusItem?.button?.appearsDisabled = !trusted || !listener.enabled
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        listener.enabled.toggle()
        UserDefaults.standard.set(listener.enabled, forKey: "enabled")
        lastError = nil
        refreshPermissions()
    }

    @objc private func changeModifier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = ModifierKey(rawValue: raw) else { return }
        modifier = key
        updateInstructions()
        lastError = nil
    }

    @objc private func openAccessibility(_ sender: Any?) {
        // Ask from this signed app's process so macOS lists the correct identity.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showGuide(_ sender: Any?) {
        if guideWindow == nil {
            let window = makeWindow(title: "Glissando", size: NSSize(width: 520, height: 400))
            let stack = contentStack(in: window)
            stack.addArrangedSubview(label("Grab a window anywhere.", size: 25, weight: .bold))
            stack.addArrangedSubview(label("Move and resize windows without reaching for their title bars or edges.", size: 14))
            let move = label("", size: 15, weight: .semibold)
            let resize = label("", size: 15, weight: .semibold)
            guideMove = move; guideResize = resize
            stack.addArrangedSubview(move)
            stack.addArrangedSubview(resize)
            stack.addArrangedSubview(label("Resize from the corner nearest the pointer. Press Esc before releasing the mouse to restore the original window.", size: 13, color: .secondaryLabelColor))
            let status = label("", size: 13)
            guideStatus = status
            stack.addArrangedSubview(status)
            let buttons = NSStackView(views: [
                NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibility(_:))),
                NSButton(title: "Try a Test Window", target: self, action: #selector(showTestWindow(_:)))
            ])
            buttons.spacing = 10
            stack.addArrangedSubview(buttons)
            guideWindow = window
        }
        updateInstructions()
        refreshPermissions()
        guideWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showTestWindow(_ sender: Any?) {
        if testWindow == nil {
            let window = makeWindow(title: "Glissando — Test Window", size: NSSize(width: 620, height: 360), resizable: true)
            window.minSize = NSSize(width: 400, height: 300)
            let stack = contentStack(in: window)
            stack.addArrangedSubview(label("Try moving this window.", size: 24, weight: .bold))
            let instructions = label("", size: 15)
            testInstructions = instructions
            stack.addArrangedSubview(instructions)
            stack.addArrangedSubview(label("Start anywhere in this window. For resizing, begin near the corner you want to drag. Esc restores the original position and size.", size: 14, color: .secondaryLabelColor))
            let dimensions = label("", size: 13, color: .secondaryLabelColor)
            dimensions.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            frameLabel = dimensions
            stack.addArrangedSubview(dimensions)
            testWindow = window
        }
        updateInstructions()
        updateFrameLabel()
        testWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateInstructions() {
        guideMove?.stringValue = "\(modifier.title) + left drag     Move window"
        guideResize?.stringValue = "\(modifier.title) + right drag   Resize window"
        testInstructions?.stringValue = "Hold \(modifier.title) and drag with the left mouse button to move, or the right mouse button to resize."
    }

    private func updateFrameLabel() {
        guard let frame = testWindow?.frame else { return }
        frameLabel?.stringValue = "Position  \(Int(frame.minX)), \(Int(frame.minY))    Size  \(Int(frame.width)) × \(Int(frame.height)) pt"
    }

    func windowDidMove(_ notification: Notification) { updateFrameLabel() }
    func windowDidResize(_ notification: Notification) { updateFrameLabel() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === testWindow {
            testWindow = nil; frameLabel = nil; testInstructions = nil
        }
    }

    private func makeWindow(title: String, size: NSSize, resizable: Bool = false) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func contentStack(in window: NSWindow) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
            ])
        }
        return stack
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}
