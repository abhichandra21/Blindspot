import AppKit

// User choices from the Settings window, stored in UserDefaults.
enum Prefs {
    static let soundKey = "playSound"
    static let tabsKey = "riskyTabs"
    static let minimizeKey = "autoMinimize"
    static let screenRequestedKey = "screenRecordingRequested"
    // Tests swap in a throwaway suite so they never touch the real settings.
    static var store: UserDefaults = .standard

    // Off until the user turns it on. Earlier versions only stored this when
    // the checkbox was clicked, so a stored value is always a real choice.
    static var autoMinimize: Bool {
        get { store.object(forKey: minimizeKey) as? Bool ?? false }
        set { store.set(newValue, forKey: minimizeKey) }
    }
    static var playSound: Bool {
        get { store.object(forKey: soundKey) as? Bool ?? true }
        set { store.set(newValue, forKey: soundKey) }
    }
    static var riskyTabs: [String] {
        get { store.stringArray(forKey: tabsKey) ?? allRiskyTabs }
        set { store.set(newValue, forKey: tabsKey) }
    }
    // Set once the macOS Screen Recording prompt has been shown, since macOS
    // only shows it once.
    static var screenRecordingRequested: Bool {
        get { store.bool(forKey: screenRequestedKey) }
        set { store.set(newValue, forKey: screenRequestedKey) }
    }
}

// Opens Settings only before the user has seen the macOS prompt, so someone
// who chose to deny is not shown a window at every login.
func shouldOpenSetupAtLaunch(screenGranted: Bool, screenRequested: Bool) -> Bool {
    !screenGranted && !screenRequested
}

enum ScreenRecordingAction: Equatable {
    case request
    case openSettings
}

// macOS shows its Screen Recording prompt only once; after that the way to
// allow it is System Settings.
func screenRecordingAction(granted: Bool, requested: Bool) -> ScreenRecordingAction {
    !granted && !requested ? .request : .openSettings
}

func screenRecordingHint(granted: Bool, requested: Bool) -> String? {
    requested && !granted ? "If you already allowed it, quit and reopen Blindspot." : nil
}

let testWarningSeconds: TimeInterval = 3

enum PreviewPlacement: Equatable {
    case anyScreen
    case sharing
    case checksOff
    case unknown
}

// The test warning is shown only while checks are running and see no Teams
// share, so a share that starts afterwards changes the state and hides it.
// Without a reliable window list a share cannot be ruled out, so it is not
// shown at all.
func previewPlacement(state: GuardState?, windows: [WindowInfo]?, permission: Bool) -> PreviewPlacement {
    guard permission, let windows else { return .unknown }
    let sharing = windows.contains { $0.owner.hasPrefix(teamsOwnerPrefix) && $0.title == sharingIndicatorTitle }
    if sharing { return .sharing }
    if state == .paused || state == .checksDisabled { return .checksOff }
    return state == .notSharing ? .anyScreen : .unknown
}

// Standard macOS settings window: toolbar tabs, each option with a short gray
// explanation underneath, like most Mac menu bar apps.
final class SettingsWindowController: NSObject {
    private let onChange: () -> Void
    private let onPreview: () -> String?
    private var window: NSWindow?
    private var tabsController: NSTabViewController?

    private let loginBox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let soundBox = NSButton(checkboxWithTitle: "Play Warning Sound", target: nil, action: nil)
    private let minimizeBox = NSButton(checkboxWithTitle: "Minimize Exposed Teams Windows", target: nil, action: nil)
    private var tabBoxes: [NSButton] = []
    private let previewButton = NSButton(title: "Show Test Warning", target: nil, action: nil)
    private let previewStatus = secondary("")
    private let loginStatus = secondary("")
    private let screenStatus = PermissionRow(
        title: "Screen Recording",
        detail: "Required. Lets the app see which Teams windows are open and when Teams is sharing.",
        settingsAnchor: "Privacy_ScreenCapture")
    private let accessibilityStatus = PermissionRow(
        title: "Accessibility",
        detail: "Needed only to minimize Teams windows during a share.",
        settingsAnchor: "Privacy_Accessibility")

    init(onChange: @escaping () -> Void, onPreview: @escaping () -> String?) {
        self.onChange = onChange
        self.onPreview = onPreview
        super.init()
        screenStatus.onButton = { [weak self] in self?.screenRecordingClicked() }
    }

    func showPermissions() {
        show()
        tabsController?.selectedTabViewItemIndex = 2
    }

    func show() {
        if window == nil { window = makeWindow() }
        refreshLogin()
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
        let screenGranted = CGPreflightScreenCaptureAccess()
        let requested = Prefs.screenRecordingRequested
        let action = screenRecordingAction(granted: screenGranted, requested: requested)
        screenStatus.update(granted: screenGranted, required: true,
                            hint: screenRecordingHint(granted: screenGranted, requested: requested),
                            buttonTitle: action == .request ? "Allow Screen Recording..." : nil)
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
        previewButton.target = self
        previewButton.action = #selector(previewClicked)
        previewStatus.isHidden = true
        loginStatus.isHidden = true
        let loginRow = NSStackView(views: [loginBox, loginStatus])
        loginRow.orientation = .vertical
        loginRow.alignment = .leading
        loginRow.spacing = 4
        let previewRow = NSStackView(views: [previewButton, previewStatus])
        previewRow.orientation = .vertical
        previewRow.alignment = .leading
        previewRow.spacing = 4

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let general = page([
            option(loginRow, "Automatically opens the app when you log in to your Mac."),
            option(soundBox, "Plays a short sound when a Teams chat may be visible in your share."),
            option(previewRow, "Shows the warning with sample text for a few seconds. "
                + "Never minimizes anything.", title: "Test Warning"),
            note("Click the menu bar shield to pause or resume. Right-click it for Settings and Quit."),
        ], footer: quit)

        let tabRow = NSStackView(views: tabBoxes)
        tabRow.spacing = 16
        let detection = page([
            option(tabRow, "Warn when these Teams tabs are on the screen you are sharing. "
                + "Both can show message text.", title: "Watch These Teams Tabs"),
            option(minimizeBox, "Minimizes those Teams windows when a whole screen is shared. "
                + "Needs Accessibility permission."),
        ])

        let permissions = page([
            note("Blindspot checks about once a second which Teams windows are on the screen you are sharing. "
                + "It reads window titles and positions on this Mac; it never captures images of your screen "
                + "or uploads anything. Minimizing is optional; choose it in Detection."),
            screenStatus.view, accessibilityStatus.view,
        ])

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

        tabsController = tabs
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

    // An unknown state keeps the checkbox as it was rather than guessing.
    private func refreshLogin() {
        let enabled = LoginItem.isEnabled
        if let enabled { loginBox.state = enabled ? .on : .off }
        if enabled == nil {
            showLoginStatus("Couldn't check Start at Login.")
        } else if LoginItem.isStale {
            showLoginStatus("Start at Login pointed at an old copy; turn it on again to fix.")
        } else {
            showLoginStatus(nil)
        }
    }

    private func showLoginStatus(_ text: String?) {
        loginStatus.stringValue = text ?? ""
        loginStatus.isHidden = text == nil
    }

    @objc private func loginChanged() {
        let wanted = loginBox.state == .on
        if let problem = LoginItem.setEnabled(wanted) {
            loginBox.state = wanted ? .off : .on
            showLoginStatus(problem)
        } else {
            refreshLogin()
        }
    }

    @objc private func soundChanged() {
        Prefs.playSound = soundBox.state == .on
    }

    @objc private func tabsChanged() {
        Prefs.riskyTabs = tabBoxes.filter { $0.state == .on }.map(\.title)
        onChange()
    }

    private func screenRecordingClicked() {
        switch screenRecordingAction(granted: CGPreflightScreenCaptureAccess(),
                                     requested: Prefs.screenRecordingRequested) {
        case .request:
            Prefs.screenRecordingRequested = true
            CGRequestScreenCaptureAccess()
        case .openSettings:
            screenStatus.openSystemSettings()
        }
        refreshPermission()
    }

    @objc private func previewClicked() {
        let problem = onPreview()
        previewStatus.stringValue = problem ?? ""
        previewStatus.isHidden = problem == nil
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
// and a button to the matching System Settings page, unless onButton replaces it.
final class PermissionRow: NSObject {
    let view: NSView
    var onButton: (() -> Void)?
    private let icon = NSImageView()
    private let status = NSTextField(labelWithString: "")
    private let hintLabel = secondary("")
    private let button = NSButton(title: "Open System Settings...", target: nil, action: nil)
    private let anchor: String

    init(title: String, detail: String, settingsAnchor: String) {
        anchor = settingsAnchor
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        let titleRow = NSStackView(views: [icon, name, status])
        titleRow.spacing = 6
        hintLabel.isHidden = true
        let stack = NSStackView(views: [titleRow, secondary(detail), hintLabel, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        view = stack
        super.init()
        button.target = self
        button.action = #selector(buttonClicked)
    }

    func update(granted: Bool, required: Bool, hint: String? = nil, buttonTitle: String? = nil) {
        hintLabel.stringValue = hint ?? ""
        hintLabel.isHidden = hint == nil
        button.title = buttonTitle ?? "Open System Settings..."

        let symbol = granted ? "checkmark.circle.fill" : (required ? "xmark.circle.fill" : "minus.circle.fill")
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = granted ? .systemGreen : (required ? .systemRed : .systemGray)
        status.stringValue = granted ? "Allowed" : "Not allowed"
        status.textColor = .secondaryLabelColor
    }

    @objc private func buttonClicked() {
        if let onButton { onButton() } else { openSystemSettings() }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
