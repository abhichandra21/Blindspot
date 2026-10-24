import AppKit
import CoreGraphics

// Blindspot: warns when a Teams chat window is visible in what you are
// screen sharing from Teams.
//
// How it detects things (found by watching the window list during a real share):
// - While sharing, Teams (the "ModuleHost" process) shows a window titled
//   "Sharing Indicator" that covers exactly the shared area: the whole display
//   for a screen share.
// - The main Teams window title starts with the current tab, e.g. "Chat | ..."
//   or "Activity | ...". Those tabs can show message content.
// Window titles are only readable with the Screen Recording permission.

let teamsOwnerPrefix = "Microsoft Teams"
let sharingIndicatorTitle = "Sharing Indicator"
let allRiskyTabs = ["Chat", "Activity"]
let pollIntervalSeconds = 1.0
let launchAgentLabel = "com.abhichandra.blindspot"

// User choices from the Settings window, stored in UserDefaults.
enum Prefs {
    static let soundKey = "playSound"
    static let tabsKey = "riskyTabs"
    static let minimizeKey = "autoMinimize"

    static var autoMinimize: Bool {
        get { UserDefaults.standard.object(forKey: minimizeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: minimizeKey) }
    }
    static var playSound: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }
    static var riskyTabs: [String] {
        get { UserDefaults.standard.stringArray(forKey: tabsKey) ?? allRiskyTabs }
        set { UserDefaults.standard.set(newValue, forKey: tabsKey) }
    }
}

// Start at login is the launchd agent in ~/Library/LaunchAgents. Turning it off
// uses `launchctl disable`, which stops future logins from starting it without
// killing the copy that is running now.
enum LoginItem {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }
    static var domain: String { "gui/\(getuid())" }

    static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }
        let out = launchctl(["print-disabled", domain])
        let disabled = out.split(separator: "\n").contains { line in
            // Lines look like: "label" => disabled   (older macOS: => true)
            line.contains("\"\(launchAgentLabel)\"") && (line.contains("=> disabled") || line.contains("=> true"))
        }
        return !disabled
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled && !FileManager.default.fileExists(atPath: plistURL.path) {
            writePlist()
        }
        _ = launchctl([enabled ? "enable" : "disable", "\(domain)/\(launchAgentLabel)"])
    }

    private static func writePlist() {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [Bundle.main.executablePath ?? CommandLine.arguments[0]],
            "RunAtLoad": true,
            // Restart after a crash, but not after Quit from the menu (clean exit).
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
        } catch {
            NSLog("Failed to write launch agent \(plistURL.path): \(error)")
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            NSLog("Failed to run launchctl \(args): \(error)")
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
// The indicator animates slightly inset while starting/stopping, so allow slack
// when deciding whether it covers a whole display.
let displayMatchSlackPoints: CGFloat = 60

struct WindowInfo: Equatable {
    let owner: String
    let pid: pid_t
    let title: String
    let layer: Int
    let bounds: CGRect
}

enum GuardState: Equatable {
    case paused
    case checksDisabled
    case noPermission
    case observationFailed
    case notSharing
    case sharingClear
    // The exposed Teams windows and the shared area, so the banner can avoid
    // the shared screen and the windows can be minimized.
    case chatExposed([WindowInfo], CGRect, wholeDisplay: Bool)

    // Only a whole-display share is clear enough to act on. A window share
    // keeps the warning, since overlap alone does not prove the chat is the
    // shared window.
    var autoMinimizeTargets: [WindowInfo] {
        if case .chatExposed(let windows, _, wholeDisplay: true) = self { return windows }
        return []
    }

    var statusText: String {
        switch self {
        case .paused: return "Paused"
        case .checksDisabled: return "Checks disabled: no Teams tabs selected"
        case .noPermission: return "Needs Screen Recording permission"
        case .observationFailed: return "Unable to check Teams sharing"
        case .notSharing: return "No Teams share detected"
        case .sharingClear: return "Sharing; no watched Teams windows detected in the shared area"
        case .chatExposed(let windows, _, _):
            return "Teams \(tabName(windows[0])) may be visible in your share"
        }
    }
}

func onScreenWindows() -> [WindowInfo]? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    return list.compactMap { w in
        guard let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        return WindowInfo(
            owner: w[kCGWindowOwnerName as String] as? String ?? "",
            pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0,
            title: w[kCGWindowName as String] as? String ?? "",
            layer: w[kCGWindowLayer as String] as? Int ?? -1,
            bounds: bounds)
    }
}

func displayBounds() -> [CGRect]? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
    return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
}

func isWholeDisplay(_ rect: CGRect, displays: [CGRect]) -> Bool {
    displays.contains { d in
        abs(d.minX - rect.minX) < displayMatchSlackPoints
            && abs(d.minY - rect.minY) < displayMatchSlackPoints
            && abs(d.width - rect.width) < displayMatchSlackPoints * 2
            && abs(d.height - rect.height) < displayMatchSlackPoints * 2
    }
}

func currentState(paused: Bool = false, riskyTabs: [String] = Prefs.riskyTabs,
                  hasPermission: () -> Bool = { CGPreflightScreenCaptureAccess() },
                  readWindows: () -> [WindowInfo]? = onScreenWindows,
                  readDisplays: () -> [CGRect]? = displayBounds) -> GuardState {
    if paused { return .paused }
    guard !riskyTabs.isEmpty else { return .checksDisabled }
    guard hasPermission() else { return .noPermission }
    guard let observedWindows = readWindows() else { return .observationFailed }
    let windows = observedWindows.filter { $0.owner.hasPrefix(teamsOwnerPrefix) }
    guard let indicator = windows.first(where: { $0.title == sharingIndicatorTitle }) else {
        return .notSharing
    }
    let shared = indicator.bounds
    guard let displays = readDisplays() else { return .observationFailed }
    let wholeDisplay = isWholeDisplay(shared, displays: displays)
    let risky = windows.filter { w in
        w.layer == 0 && riskyTabs.contains { w.title.hasPrefix($0) }
    }
    let exposed = risky.filter { w in
        let overlap = w.bounds.intersection(shared)
        if overlap.isNull || overlap.isEmpty { return false }
        // Screen share: any part of the chat on that display is visible.
        // Window share: only flag it if the shared window is the chat itself.
        let overlapArea = overlap.width * overlap.height
        let sharedArea = shared.width * shared.height
        return wholeDisplay || overlapArea >= sharedArea * 0.5
    }
    return exposed.isEmpty ? .sharingClear : .chatExposed(exposed, shared, wholeDisplay: wholeDisplay)
}

func tabName(_ w: WindowInfo) -> String {
    w.title.components(separatedBy: " |").first ?? w.title
}

// Window list and Accessibility frames are both in global top-left points;
// this only absorbs rounding, not a moved or resized window.
let axFrameMatchSlackPoints: CGFloat = 1

// An Accessibility window as read for matching; nil where an attribute could not be read.
struct AXWindowCandidate {
    let title: String?
    let frame: CGRect?
}

enum AXWindowMatch: Equatable {
    case match(Int)
    case ambiguous
    case stale
    case unreadable
}

enum MinimizeOutcome: Equatable {
    case minimized
    case skippedAmbiguous
    case skippedStale
    case skippedUnreadable
    case failed(AXError)
}

// Acts only on one window with the observed title and frame. A duplicate,
// a changed window, or one that cannot be read is left alone.
func matchAXWindow(_ target: WindowInfo, in candidates: [AXWindowCandidate]) -> AXWindowMatch {
    func frameMatches(_ frame: CGRect) -> Bool {
        abs(frame.minX - target.bounds.minX) <= axFrameMatchSlackPoints
            && abs(frame.minY - target.bounds.minY) <= axFrameMatchSlackPoints
            && abs(frame.width - target.bounds.width) <= axFrameMatchSlackPoints
            && abs(frame.height - target.bounds.height) <= axFrameMatchSlackPoints
    }
    // A candidate is ruled out by any readable attribute that differs.
    let possible = candidates.indices.filter { i in
        let c = candidates[i]
        return (c.title == nil || c.title == target.title) && (c.frame.map(frameMatches) ?? true)
    }
    if possible.contains(where: { candidates[$0].title == nil || candidates[$0].frame == nil }) {
        return .unreadable
    }
    switch possible.count {
    case 0: return .stale
    case 1: return .match(possible[0])
    default: return .ambiguous
    }
}

func axCandidate(_ window: AXUIElement) -> AXWindowCandidate {
    func copy(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return nil }
        return value
    }
    func axValue(_ attribute: String) -> AXValue? {
        guard let value = copy(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    var frame: CGRect?
    if let positionValue = axValue(kAXPositionAttribute), AXValueGetValue(positionValue, .cgPoint, &position),
       let sizeValue = axValue(kAXSizeAttribute), AXValueGetValue(sizeValue, .cgSize, &size) {
        frame = CGRect(origin: position, size: size)
    }
    return AXWindowCandidate(title: copy(kAXTitleAttribute) as? String, frame: frame)
}

// Minimizes Teams windows through the Accessibility API, matching the window
// list entries to accessibility windows by title and frame. Needs Accessibility permission.
@discardableResult
func minimize(_ windows: [WindowInfo]) -> [MinimizeOutcome] {
    var outcomes: [MinimizeOutcome] = []
    for (pid, group) in Dictionary(grouping: windows, by: \.pid) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard readResult == .success, let axWindows = value as? [AXUIElement] else {
            let error = readResult == .success ? AXError.failure : readResult
            NSLog("Failed to read Teams windows: AX error \(error.rawValue)")
            outcomes += group.map { _ in .failed(error) }
            continue
        }
        let candidates = axWindows.map(axCandidate)
        for target in group {
            switch matchAXWindow(target, in: candidates) {
            case .match(let index):
                let result = AXUIElementSetAttributeValue(axWindows[index], kAXMinimizedAttribute as CFString,
                                                          kCFBooleanTrue)
                if result == .success {
                    outcomes.append(.minimized)
                } else {
                    NSLog("Failed to minimize Teams window: AX error \(result.rawValue)")
                    outcomes.append(.failed(result))
                }
            case .ambiguous: outcomes.append(.skippedAmbiguous)
            case .stale: outcomes.append(.skippedStale)
            case .unreadable: outcomes.append(.skippedUnreadable)
            }
        }
    }
    return outcomes
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private var warningPanel: NSPanel?
    private var state: GuardState?
    // Not saved on purpose: every launch starts unpaused so a pause is never forgotten.
    private var paused = false
    private lazy var settings = SettingsWindowController { [weak self] in
        // A changed tab choice should take effect now, not on the next change.
        self?.state = nil
        self?.refresh()
    }

    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
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

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        if Prefs.autoMinimize { requestAccessibility() }
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
        // Retry every tick while exposed, so it still works once permission is granted.
        let targets = newState.autoMinimizeTargets
        if !targets.isEmpty, Prefs.autoMinimize, AXIsProcessTrusted() {
            minimize(targets)
        }
        guard newState != state else { return }
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
        statusItem.button?.toolTip = "\(text)\nClick to \(paused ? "resume" : "pause"), right-click for menu"
        statusLine.title = text
    }

    // A small floating banner, shown only on a screen that is not being shared.
    // sharingType = .none does not reliably hide windows from ScreenCaptureKit,
    // so with no unshared screen we skip the banner and rely on sound + icon.
    private func showWarning(_ text: String, avoiding shared: CGRect) {
        let unshared = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return false }
            return !CGDisplayBounds(id).intersects(shared)
        }
        guard let screen = unshared else {
            hideWarning()
            return
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
        guard let panel = warningPanel else { return }
        (panel.contentView?.viewWithTag(1) as? NSTextField)?.stringValue = text
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 12))
        panel.orderFrontRegardless()
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

// Shows the macOS prompt that sends the user to the Accessibility list.
func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

// Standard macOS settings window: toolbar tabs, each option with a short gray
// explanation underneath, like most Mac menu bar apps.
final class SettingsWindowController: NSObject {
    private let onChange: () -> Void
    private var window: NSWindow?

    private let loginBox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let soundBox = NSButton(checkboxWithTitle: "Play Warning Sound", target: nil, action: nil)
    private let minimizeBox = NSButton(checkboxWithTitle: "Minimize Exposed Teams Windows", target: nil, action: nil)
    private var tabBoxes: [NSButton] = []
    private let screenStatus = PermissionRow(
        title: "Screen Recording",
        detail: "Required. Lets the app see which Teams windows are open and when Teams is sharing.",
        settingsAnchor: "Privacy_ScreenCapture")
    private let accessibilityStatus = PermissionRow(
        title: "Accessibility",
        detail: "Needed only to minimize Teams windows during a share.",
        settingsAnchor: "Privacy_Accessibility")

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func show() {
        if window == nil { window = makeWindow() }
        loginBox.state = LoginItem.isEnabled ? .on : .off
        soundBox.state = Prefs.playSound ? .on : .off
        minimizeBox.state = Prefs.autoMinimize ? .on : .off
        let tabs = Prefs.riskyTabs
        for box in tabBoxes { box.state = tabs.contains(box.title) ? .on : .off }
        // An accessory app has to activate itself or the window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        // After ordering front: refreshPermission skips hidden windows.
        refreshPermission()
    }

    func refreshPermission() {
        guard window?.isVisible == true else { return }
        screenStatus.update(granted: CGPreflightScreenCaptureAccess(), required: true)
        accessibilityStatus.update(granted: AXIsProcessTrusted(), required: Prefs.autoMinimize)
    }

    private func makeWindow() -> NSWindow {
        loginBox.target = self
        loginBox.action = #selector(loginChanged)
        soundBox.target = self
        soundBox.action = #selector(soundChanged)
        minimizeBox.target = self
        minimizeBox.action = #selector(minimizeChanged)
        tabBoxes = allRiskyTabs.map { NSButton(checkboxWithTitle: $0, target: self, action: #selector(tabsChanged)) }

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let general = page([
            option(loginBox, "Automatically opens the app when you log in to your Mac."),
            option(soundBox, "Plays a short sound when a Teams chat may be visible in your share."),
            note("Click the menu bar shield to pause or resume. Right-click it for Settings and Quit."),
        ], footer: quit)

        let tabRow = NSStackView(views: tabBoxes)
        tabRow.spacing = 16
        let detection = page([
            option(tabRow, "Warn when these Teams tabs are on the screen you are sharing. "
                + "Both can show message text.", title: "Watch These Teams Tabs"),
            option(minimizeBox, "Minimizes those Teams windows as soon as a share starts. "
                + "Needs Accessibility permission."),
        ])

        let permissions = page([screenStatus.view, accessibilityStatus.view])

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for (label, symbol, view) in [
            ("General", "gearshape", general),
            ("Detection", "eye", detection),
            ("Permissions", "lock.shield", permissions),
            ("About", "info.circle", aboutPage()),
        ] {
            let vc = NSViewController()
            vc.view = view
            // Size each tab to its content, so the window shrinks and grows per tab
            // instead of staying as tall as the tallest one.
            view.layoutSubtreeIfNeeded()
            vc.preferredContentSize = view.fittingSize
            let item = NSTabViewItem(viewController: vc)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }

        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]
        w.title = "Blindspot Settings"
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        return w
    }

    private func aboutPage() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 48, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        let name = NSTextField(labelWithString: "Blindspot")
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLabel = secondary("Version \(version)")
        let blurb = NSTextField(wrappingLabelWithString:
            "Warns you, and can minimize Teams, when a Teams chat may be visible in a Teams screen share.")
        blurb.alignment = .center
        blurb.preferredMaxLayoutWidth = 380
        let path = secondary(Bundle.main.bundlePath)
        path.isSelectable = true
        path.lineBreakMode = .byTruncatingMiddle
        path.preferredMaxLayoutWidth = 380

        let stack = NSStackView(views: [icon, name, versionLabel, blurb, path])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(14, after: versionLabel)
        stack.setCustomSpacing(14, after: blurb)
        return framed(stack, centered: true)
    }

    // A control (usually a checkbox) with a gray explanation lined up under its text.
    private func option(_ control: NSView, _ detail: String, title: String? = nil) -> NSView {
        var views: [NSView] = []
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            views.append(label)
        }
        views.append(control)
        // Under a lone checkbox, indent to its text rather than the box.
        let detailRow = NSStackView(views: [secondary(detail)])
        detailRow.edgeInsets = NSEdgeInsets(top: 0, left: title == nil ? 20 : 0, bottom: 0, right: 0)
        detailRow.setHuggingPriority(.required, for: .vertical)
        views.append(detailRow)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)
        return stack
    }

    private func note(_ text: String) -> NSView {
        let label = secondary(text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    private func page(_ rows: [NSView], footer: NSView? = nil) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setHuggingPriority(.required, for: .vertical)
        guard let footer else { return framed(stack, centered: false) }

        let line = NSBox()
        line.boxType = .separator
        let footerRow = NSStackView(views: [NSView(), footer])
        footerRow.distribution = .fill
        let outer = NSStackView(views: [stack, line, footerRow])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 16
        for v in [line, footerRow] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        }
        return framed(outer, centered: false)
    }

    private func framed(_ content: NSStackView, centered: Bool) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 440),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: centered ? 30 : 40),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: centered ? -40 : -30),
        ])
        return container
    }

    @objc private func loginChanged() {
        LoginItem.setEnabled(loginBox.state == .on)
        loginBox.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func soundChanged() {
        Prefs.playSound = soundBox.state == .on
    }

    @objc private func tabsChanged() {
        Prefs.riskyTabs = tabBoxes.filter { $0.state == .on }.map(\.title)
        onChange()
    }

    @objc private func minimizeChanged() {
        Prefs.autoMinimize = minimizeBox.state == .on
        if Prefs.autoMinimize && !AXIsProcessTrusted() { requestAccessibility() }
        refreshPermission()
    }
}

func secondary(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
    label.preferredMaxLayoutWidth = 360
    // Wrapping labels in stack views otherwise stretch to fill spare height.
    label.setContentHuggingPriority(.required, for: .vertical)
    return label
}

// One permission: a green check or red cross, its name, why it is needed,
// and a button to the matching System Settings page.
final class PermissionRow: NSObject {
    let view: NSView
    private let icon = NSImageView()
    private let status = NSTextField(labelWithString: "")
    private let anchor: String

    init(title: String, detail: String, settingsAnchor: String) {
        anchor = settingsAnchor
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        let titleRow = NSStackView(views: [icon, name, status])
        titleRow.spacing = 6
        let button = NSButton(title: "Open System Settings...", target: nil, action: nil)
        let stack = NSStackView(views: [titleRow, secondary(detail), button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        view = stack
        super.init()
        button.target = self
        button.action = #selector(openSettings)
    }

    func update(granted: Bool, required: Bool) {
        let symbol = granted ? "checkmark.circle.fill" : (required ? "xmark.circle.fill" : "minus.circle.fill")
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = granted ? .systemGreen : (required ? .systemRed : .systemGray)
        status.stringValue = granted ? "Allowed" : "Not allowed"
        status.textColor = .secondaryLabelColor
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if BLINDSPOT_TESTING
StatusTests.main()
#else
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
#endif
