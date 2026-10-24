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
            show(symbol: "shield", text: newState.statusText)
            hideWarning()
        case .checksDisabled:
            show(symbol: "shield", text: newState.statusText)
            hideWarning()
        case .noPermission:
            show(symbol: "lock.shield.fill", text: newState.statusText)
            hideWarning()
        case .observationFailed:
            show(symbol: "exclamationmark.shield.fill", text: newState.statusText, tint: .systemOrange)
            hideWarning()
        case .notSharing:
            show(symbol: "shield.fill", text: newState.statusText)
            hideWarning()
        case .sharingClear:
            show(symbol: "checkmark.shield.fill", text: newState.statusText)
            hideWarning()
        case .chatExposed(let windows, let shared, _):
            let tab = tabName(windows[0])
            // Overlap is by window bounds, so a chat hidden behind another
            // window still counts. Hence "may be".
            show(symbol: "exclamationmark.shield.fill", text: newState.statusText,
                 tint: .systemRed)
            if !wasExposed && Prefs.playSound { NSSound(named: "Funk")?.play() }
            showWarning("Teams \(tab) may be visible in your screen share", avoiding: shared)
        }
    }

    // Like a full or empty cup: filled shield while checking, outline while
    // paused or disabled. Warning is red.
    private func show(symbol: String, text: String, tint: NSColor? = nil) {
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        if let tint {
            image = image?.withSymbolConfiguration(.init(paletteColors: [tint]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
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
