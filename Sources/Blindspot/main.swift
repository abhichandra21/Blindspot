import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let minimizeNoteLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let attempts = MinimizeAttempts()
    private var minimizeNoteText: String?
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private var warningPanel: NSPanel?
    private var state: GuardState?
    // Not saved on purpose: every launch starts unpaused so a pause is never forgotten.
    private var paused = false
    private lazy var settings = SettingsWindowController(onChange: { [weak self] in
        // A changed tab choice should take effect now, not on the next change.
        self?.state = nil
        self?.refresh()
    }, onPreview: { [weak self] in
        self?.showTestWarning()
    })

    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        minimizeNoteLine.isEnabled = false
        minimizeNoteLine.isHidden = true
        menu.addItem(minimizeNoteLine)
        menu.addItem(.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Blindspot",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Like Keeping You Awake: left-click pauses/resumes, right-click opens
        // the menu. No statusItem.menu, or every click would open the menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Explain before macOS asks: Settings opens on Permissions, and the
        // prompt appears only when the user clicks the button there.
        if shouldOpenSetupAtLaunch(screenGranted: CGPreflightScreenCaptureAccess(),
                                   screenRequested: Prefs.screenRecordingRequested) {
            settings.showPermissions()
        }
        // On the system-wide element this sets the timeout for every
        // Accessibility element this app talks to, not just that one.
        let timeoutResult = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axMessagingTimeoutSeconds)
        if timeoutResult != .success { NSLog("Failed to set Accessibility timeout: AX error \(timeoutResult.rawValue)") }
        // Common mode keeps the timer firing while the menu is open.
        let timer = Timer(timeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    private func refresh() {
        let newState = currentState(paused: paused)
        settings.refreshPermission()
        if newState != state { showState(newState) }
        // Started after the warning is shown and run off the main thread, so a
        // slow Teams cannot hold up the warning.
        let trusted = AXIsProcessTrusted()
        let targets = minimizeAttemptTargets(newState, autoMinimize: Prefs.autoMinimize, trusted: trusted)
        if targets.isEmpty {
            attempts.cancel()
            setMinimizeNote(accessibilityNote(newState, autoMinimize: Prefs.autoMinimize, trusted: trusted))
        } else {
            attempts.start(targets) { [weak self] outcomes in self?.minimizeFinished(outcomes) }
        }
    }

    private func minimizeFinished(_ outcomes: [MinimizeOutcome]) {
        let note = minimizeNote(outcomes)
        if let note, note != minimizeNoteText {
            let errors = outcomes.compactMap { if case .failed(let error) = $0 { return error.rawValue } else { return nil } }
            NSLog("\(note); AX errors \(errors)")
        }
        setMinimizeNote(note)
    }

    private func setMinimizeNote(_ note: String?) {
        guard note != minimizeNoteText else { return }
        minimizeNoteText = note
        minimizeNoteLine.title = note ?? ""
        minimizeNoteLine.isHidden = note == nil
        updateToolTip()
    }

    private func showState(_ newState: GuardState) {
        let wasExposed = { if case .chatExposed = self.state { return true } else { return false } }()
        state = newState

        switch newState {
        case .paused:
            show(menuBarImage(solid: false), text: newState.statusText)
            hideWarning()
        case .checksDisabled:
            show(menuBarImage(solid: false), text: newState.statusText)
            hideWarning()
        case .noPermission:
            show(menuBarImage(solid: false, dot: .systemOrange), text: newState.statusText)
            hideWarning()
        case .observationFailed:
            show(menuBarImage(solid: false, dot: .systemOrange), text: newState.statusText)
            hideWarning()
        case .notSharing:
            show(menuBarImage(solid: true), text: newState.statusText)
            hideWarning()
        case .sharingClear:
            show(menuBarImage(solid: true), text: newState.statusText)
            hideWarning()
        case .chatExposed(let windows, let shared, _):
            let tab = tabName(windows[0])
            // Overlap is by window bounds, so a chat hidden behind another
            // window still counts. Hence "may be".
            show(menuBarImage(solid: true, exposed: true), text: newState.statusText)
            if !wasExposed && Prefs.playSound { NSSound(named: "Funk")?.play() }
            showWarning("Teams \(tab) may be visible in your screen share", avoiding: shared)
        }
    }

    private func show(_ image: NSImage, text: String) {
        image.accessibilityDescription = text
        statusItem.button?.image = image
        statusLine.title = text
        updateToolTip()
    }

    private func updateToolTip() {
        let note = minimizeNoteText.map { "\n\($0)" } ?? ""
        statusItem.button?.toolTip =
            "\(statusLine.title)\(note)\nClick to \(paused ? "resume" : "pause"), right-click for menu"
    }

    // A small floating banner, shown only on a screen that is not being shared.
    // sharingType = .none does not reliably hide windows from ScreenCaptureKit,
    // so with no unshared screen we skip the banner and rely on sound + icon.
    @discardableResult
    private func showWarning(_ text: String, avoiding shared: CGRect) -> Bool {
        let unshared = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return false }
            return !CGDisplayBounds(id).intersects(shared)
        }
        guard let screen = unshared else {
            hideWarning()
            return false
        }
        if warningPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.backgroundColor = .systemRed
            panel.isOpaque = true
            panel.hasShadow = true
            let label = NSTextField(labelWithString: "")
            label.font = .boldSystemFont(ofSize: 15)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 12, y: 17, width: 396, height: 22)
            label.tag = 1
            panel.contentView?.addSubview(label)
            warningPanel = panel
        }
        guard let panel = warningPanel else { return false }
        (panel.contentView?.viewWithTag(1) as? NSTextField)?.stringValue = text
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 12))
        panel.orderFrontRegardless()
        return true
    }

    // Shows the banner and plays the sound with sample text. Never minimizes.
    // Returns why nothing was shown, or nil.
    private func showTestWarning() -> String? {
        if case .chatExposed = state { return "A real warning is showing." }
        switch previewPlacement(state: state, windows: onScreenWindows(),
                                permission: CGPreflightScreenCaptureAccess()) {
        case .unknown: return "Can't show a test banner without confirming no screen is being shared."
        case .sharing: return "Stop sharing to show a test warning."
        case .checksOff: return "Resume checks to show a test warning."
        case .anyScreen: break
        }
        guard showWarning("Test: Teams Chat may be visible in your screen share", avoiding: .null) else {
            return "No screen available to show the test banner on."
        }
        if Prefs.playSound { NSSound(named: "Funk")?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + testWarningSeconds) { [weak self] in
            guard let self else { return }
            if case .chatExposed = self.state { return }
            self.hideWarning()
        }
        return nil
    }

    private func hideWarning() {
        warningPanel?.orderOut(nil)
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard wantsMenu else {
            togglePause()
            return
        }
        // Attach the menu just for this click, then detach so left-click keeps toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume" : "Pause"
        refresh()
    }
}

// `--once` prints the current state and exits, for testing from a terminal.
if CommandLine.arguments.contains("--once") {
    print(currentState())
    exit(0)
}

// A small display with an eye on it: your screen is being seen. A solid eye
// while watching, an outline eye while off, all red when a chat may be exposed.
// A dot means Blindspot needs something. Without color the image is a
// template, so macOS colors it like the rest of the menu bar.
func menuBarImage(solid: Bool, exposed: Bool = false, dot: NSColor? = nil) -> NSImage {
    let iconSize = NSSize(width: 22, height: 16)
    let dotDiameter: CGFloat = 7
    // Room for the dot above and to the right of the display.
    let dotRoom = dot == nil ? NSSize.zero : NSSize(width: 3, height: 2)
    let size = NSSize(width: iconSize.width + dotRoom.width, height: iconSize.height + dotRoom.height)
    // Flipped, so coordinates run top-down like the design mock-ups.
    let image = NSImage(size: size, flipped: true) { _ in
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: dotRoom.height)
        shift.concat()
        let ink = exposed ? NSColor.systemRed : NSColor.black
        ink.set()

        let screen = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 1.4, width: 18.8, height: 11), xRadius: 2, yRadius: 2)
        screen.lineWidth = 1.3
        screen.stroke()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 8, y: 15))
        stand.line(to: NSPoint(x: 14, y: 15))
        stand.lineWidth = 1.4
        stand.lineCapStyle = .round
        stand.stroke()

        let center = NSPoint(x: 11, y: 6.9)
        func circle(_ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        if solid {
            // A ring cut around the pupil, like Apple's eye.fill.
            eyePath(center: center, halfWidth: 5.4, halfHeight: 3.1).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            circle(2.4).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            circle(1.4).fill()
        } else {
            let eye = eyePath(center: center, halfWidth: 5, halfHeight: 2.9)
            eye.lineWidth = 1.3
            eye.lineJoinStyle = .round
            eye.stroke()
            circle(1.3).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let dot else { return true }
        // Not a template once it has a dot, so match the menu bar text color.
        NSColor.labelColor.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: size.width - dotDiameter, y: 0, width: dotDiameter, height: dotDiameter)).fill()
        return true
    }
    image.isTemplate = !exposed && dot == nil
    return image
}

private func eyePath(center c: NSPoint, halfWidth w: CGFloat, halfHeight h: CGFloat) -> NSBezierPath {
    // Cubic control points at 4/3 of the height give a peak of exactly h.
    let path = NSBezierPath()
    path.move(to: NSPoint(x: c.x - w, y: c.y))
    path.curve(to: NSPoint(x: c.x + w, y: c.y),
               controlPoint1: NSPoint(x: c.x - w / 2, y: c.y - h * 4 / 3),
               controlPoint2: NSPoint(x: c.x + w / 2, y: c.y - h * 4 / 3))
    path.curve(to: NSPoint(x: c.x - w, y: c.y),
               controlPoint1: NSPoint(x: c.x + w / 2, y: c.y + h * 4 / 3),
               controlPoint2: NSPoint(x: c.x - w / 2, y: c.y + h * 4 / 3))
    path.close()
    return path
}

// One copy only. macOS "Quit & Reopen" after a permission grant can start a
// second copy next to the login one, which would double every warning.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .filter { $0.processIdentifier != getpid() }
if !others.isEmpty {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
