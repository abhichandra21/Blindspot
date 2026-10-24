import CoreGraphics
import Foundation
import XCTest
@testable import Blindspot

final class StatusTests: XCTestCase {
    func checkText(_ state: GuardState, _ expected: String, _ name: String) {
        XCTAssertEqual(state.statusText, expected, name)
    }

    func window(_ title: String, _ bounds: CGRect, owner: String = teamsOwnerPrefix,
                layer: Int = 0) -> WindowInfo {
        WindowInfo(owner: owner, pid: 123, title: title, layer: layer, bounds: bounds)
    }

    let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
    lazy var indicator = window(sharingIndicatorTitle, display)
    lazy var chat = window("Chat | Synthetic", CGRect(x: 1100, y: 100, width: 300, height: 300))
    lazy var outside = window("Chat | Synthetic", CGRect(x: 1400, y: 100, width: 300, height: 300))
    let clearText = "Sharing; no watched Teams windows detected in the shared area"
    let disabledText = "Checks disabled: no Teams tabs selected"
    let failureText = "Unable to check Teams sharing"

    func detect(_ windows: [WindowInfo]?, tabs: [String] = allRiskyTabs,
                permission: Bool = true, paused: Bool = false,
                displays: [CGRect]? = nil) -> GuardState {
        currentState(paused: paused, riskyTabs: tabs, hasPermission: { permission },
                     readWindows: { windows }, readDisplays: { displays ?? [display] })
    }

    // Used by several sections; built exactly as in their first section.
    var otherIndicator: WindowInfo { window(sharingIndicatorTitle, display, owner: "Other App") }
    var displayShare: GuardState { detect([indicator, chat]) }
    var windowShare: GuardState {
        let presentation = CGRect(x: 100, y: 100, width: 600, height: 400)
        return detect([window(sharingIndicatorTitle, presentation), window("Chat | Synthetic", presentation)])
    }

    func testStatuses() {
        checkText(detect([indicator, chat], tabs: []), disabledText,
                  "no selected tabs must not report a clear share")
        checkText(detect(nil), failureText, "failed window observation must not report no share")
        checkText(detect([]), "No Teams share detected", "valid empty window list")
        checkText(detect([chat]), "No Teams share detected", "no matching share indicator")
        checkText(detect([indicator, outside]), clearText, "watched window outside the shared area")
        checkText(detect([indicator]), clearText, "share without a watched window")
    }

    func testObservationOrder() {
        var permissionReads = 0
        var windowReads = 0
        var displayReads = 0
        func observed(paused: Bool = false, tabs: [String] = allRiskyTabs,
                      permission: Bool = true, windows: [WindowInfo]? = nil) -> GuardState {
            currentState(paused: paused, riskyTabs: tabs, hasPermission: {
                permissionReads += 1
                return permission
            }, readWindows: {
                windowReads += 1
                return windows
            }, readDisplays: {
                displayReads += 1
                return nil
            })
        }

        XCTAssertTrue(observed(paused: true, tabs: [], permission: false) == .paused,
              "pause takes precedence over disabled checks, permission and failed observation")
        XCTAssertTrue(permissionReads == 0 && windowReads == 0 && displayReads == 0,
              "paused checks do not observe permission, windows or displays")
        checkText(observed(tabs: [], permission: false), disabledText,
                  "disabled checks take precedence over missing permission")
        XCTAssertTrue(permissionReads == 0 && windowReads == 0 && displayReads == 0,
              "disabled checks do not observe permission, windows or displays")
        permissionReads = 0
        windowReads = 0
        displayReads = 0
        XCTAssertTrue(observed(permission: false) == .noPermission,
              "permission denial takes precedence over failed window observation")
        XCTAssertTrue(permissionReads == 1 && windowReads == 0 && displayReads == 0,
              "permission denial does not read windows or displays")
        checkText(observed(), failureText, "failed window observation with checks enabled")
        XCTAssertTrue(displayReads == 0, "failed window observation does not read displays")
        checkText(observed(windows: []), "No Teams share detected",
                  "no share result does not require display observation")
        XCTAssertTrue(displayReads == 0, "no share does not read displays")
        checkText(observed(windows: [indicator, chat]), failureText,
                  "failed display observation must not classify a detected share")
        XCTAssertTrue(displayReads == 1, "detected share reads display observation")
    }

    func testExposure() {
        checkText(detect([], permission: false), "Needs Screen Recording permission",
                  "permission status wording is preserved")
        checkText(detect([], paused: true), "Paused", "pause status wording is preserved")
        checkText(detect([indicator, chat]), "Teams Chat may be visible in your share",
                  "warning status wording is preserved")
        XCTAssertTrue(detect([indicator, chat]) == .chatExposed([chat], display, wholeDisplay: true),
              "partial display exposure remains a warning")
        let coveringWindow = window("Synthetic cover", display, owner: "Other App")
        XCTAssertTrue(detect([coveringWindow, indicator, chat]) == .chatExposed([chat], display, wholeDisplay: true),
              "a watched window behind another app still counts")
        let activity = window("Activity | Synthetic", chat.bounds)
        XCTAssertTrue(detect([indicator, activity], tabs: ["Activity"]) == .chatExposed([activity], display, wholeDisplay: true),
              "selected Activity tab remains watched")
        XCTAssertTrue(detect([indicator, chat], tabs: ["Activity"]) == .sharingClear,
              "unselected Chat tab does not trigger exposure")
        let otherIndicator = window(sharingIndicatorTitle, display, owner: "Other App")
        XCTAssertTrue(detect([otherIndicator, chat]) == .notSharing,
              "another app's indicator does not count as a Teams share")
        let otherChat = window("Chat | Synthetic", chat.bounds, owner: "Other App")
        XCTAssertTrue(detect([indicator, otherChat]) == .sharingClear,
              "another app's Chat title does not count as a watched window")
        let nonstandardLayer = window("Chat | Synthetic", chat.bounds, layer: 1)
        XCTAssertTrue(detect([indicator, nonstandardLayer]) == .sharingClear,
              "existing window layer filter is preserved")

        let sharedWindow = CGRect(x: 100, y: 100, width: 400, height: 400)
        let windowIndicator = window(sharingIndicatorTitle, sharedWindow)
        let halfOverlap = window("Chat | Synthetic", CGRect(x: 300, y: 100, width: 400, height: 400))
        let lessOverlap = window("Chat | Synthetic", CGRect(x: 301, y: 100, width: 400, height: 400))
        XCTAssertTrue(detect([windowIndicator, halfOverlap]) == .chatExposed([halfOverlap], sharedWindow, wholeDisplay: false),
              "existing window-share 50 percent threshold is preserved")
        XCTAssertTrue(detect([windowIndicator, lessOverlap]) == .sharingClear,
              "existing window-share below-threshold result is preserved")

        XCTAssertTrue(detect([indicator, chat]).autoMinimizeTargets == [chat],
              "display share with partial Chat overlap may be minimized")
        let secondDisplay = CGRect(x: 1200, y: 0, width: 1200, height: 800)
        let chatOnSecond = window("Chat | Synthetic", CGRect(x: 1400, y: 100, width: 300, height: 300))
        XCTAssertTrue(detect([indicator, chatOnSecond], displays: [display, secondDisplay]) == .sharingClear,
              "Chat on another display does not warn")
        let presentation = CGRect(x: 100, y: 100, width: 600, height: 400)
        let presentationIndicator = window(sharingIndicatorTitle, presentation)
        let chatBehind = window("Chat | Synthetic", presentation)
        let windowShare = detect([presentationIndicator, chatBehind])
        XCTAssertTrue(windowShare == .chatExposed([chatBehind], presentation, wholeDisplay: false),
              "Chat behind a shared presentation window still warns")
        XCTAssertTrue(windowShare.autoMinimizeTargets.isEmpty,
              "window share is not automatically minimized")
        XCTAssertTrue(GuardState.sharingClear.autoMinimizeTargets.isEmpty, "clear share has nothing to minimize")
    }

    func testAXMatching() {
        let target = window("Chat | Synthetic", CGRect(x: 100, y: 100, width: 300, height: 300))
        let elsewhere = CGRect(x: 500, y: 100, width: 300, height: 300)
        func candidate(_ title: String?, _ frame: CGRect?) -> AXWindowCandidate {
            AXWindowCandidate(title: title, frame: frame)
        }
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Chat | Synthetic", elsewhere),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "same-title AX windows are told apart by position")
        let rounded = target.bounds.offsetBy(dx: 0.5, dy: -0.5)
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Chat | Synthetic", rounded)]) == .match(0),
              "sub-point rounding still matches")
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Chat | Synthetic", target.bounds),
                                         candidate("Chat | Synthetic", target.bounds)]) == .ambiguous,
              "two indistinguishable AX windows are ambiguous")
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Chat | Synthetic", elsewhere)]) == .stale,
              "a moved window is stale")
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Calendar | Synthetic", target.bounds)]) == .stale,
              "a retitled window is stale")
        XCTAssertTrue(matchAXWindow(target, in: [candidate(nil, target.bounds)]) == .unreadable,
              "an unreadable title is not guessed")
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Chat | Synthetic", nil)]) == .unreadable,
              "an unreadable frame is not guessed")
        XCTAssertTrue(matchAXWindow(target, in: [candidate("Calendar | Synthetic", nil),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "an unreadable frame on another title does not block a clear match")
        XCTAssertTrue(matchAXWindow(target, in: [candidate(nil, elsewhere),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "an untitled window elsewhere does not block a clear match")
        XCTAssertTrue(matchAXWindow(target, in: [candidate(nil, nil)]) == .unreadable,
              "an untitled window with no frame is not guessed")
    }

    func testAttemptTargets() {
        let displayShare = detect([indicator, chat])
        XCTAssertTrue(minimizeAttemptTargets(displayShare, autoMinimize: true, trusted: true) == [chat],
              "display share with minimizing on is attempted")
        XCTAssertTrue(minimizeAttemptTargets(displayShare, autoMinimize: false, trusted: true).isEmpty,
              "no attempt when minimizing is off")
        XCTAssertTrue(minimizeAttemptTargets(displayShare, autoMinimize: true, trusted: false).isEmpty,
              "no attempt without Accessibility trust")
        XCTAssertTrue(minimizeAttemptTargets(windowShare, autoMinimize: true, trusted: true).isEmpty,
              "no attempt for a window share")
        XCTAssertTrue(minimizeAttemptTargets(.paused, autoMinimize: true, trusted: true).isEmpty,
              "no attempt while paused")
    }

    func testMinimizeAttempts() {
        var performed = 0
        var background: [() -> Void] = []
        var mainQueue: [() -> Void] = []
        var delivered: [[MinimizeOutcome]] = []
        var nextOutcomes: [MinimizeOutcome] = [.failed(.cannotComplete)]
        var betweenReadAndWrite: () -> Void = {}
        var writes = 0
        let attempts = MinimizeAttempts(perform: { _, stillWanted in
            performed += 1
            betweenReadAndWrite()
            guard stillWanted() else { return [.cancelled] }
            writes += 1
            return nextOutcomes
        }, runAsync: { background.append($0) }, deliver: { mainQueue.append($0) })
        func runPending() {
            let work = background
            background = []
            work.forEach { $0() }
            let results = mainQueue
            mainQueue = []
            results.forEach { $0() }
        }

        attempts.start([chat]) { delivered.append($0) }
        XCTAssertTrue(performed == 0 && delivered.isEmpty, "starting an attempt does not run it on the caller")
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        XCTAssertTrue(performed == 1 && delivered == [[.failed(.cannotComplete)]],
              "only one attempt runs while one is in flight")
        nextOutcomes = [.minimized]
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        XCTAssertTrue(performed == 2 && delivered.last == [.minimized], "a failed attempt is retried on the next start")

        delivered = []
        attempts.start([chat]) { delivered.append($0) }
        attempts.cancel()
        attempts.start([chat]) { delivered.append($0) }
        XCTAssertTrue(background.count <= 1, "cancel does not allow a second attempt while the first runs")
        runPending()
        XCTAssertTrue(performed == 3, "cancel and restart before the old attempt finishes runs it only once")
        XCTAssertTrue(delivered.isEmpty, "a cancelled attempt's result is dropped")
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        XCTAssertTrue(performed == 4 && delivered == [[.minimized]], "after the cancelled attempt finishes, a new one runs")
        XCTAssertTrue(writes == 3, "an attempt cancelled before it runs makes no write")

        delivered = []
        betweenReadAndWrite = { attempts.cancel() }
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        XCTAssertTrue(performed == 5 && writes == 3, "a cancel between reading and writing stops the write")
        XCTAssertTrue(delivered.isEmpty, "a cancel between reading and writing drops the result")
        betweenReadAndWrite = {}
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        XCTAssertTrue(writes == 4 && delivered == [[.minimized]], "the next attempt after that cancel writes")
    }

    func testMinimizeNotes() {
        XCTAssertTrue(minimizeNote([]) == nil, "no note when nothing was attempted")
        XCTAssertTrue(minimizeNote([.minimized, .minimized]) == nil, "no note when everything was minimized")
        XCTAssertTrue(minimizeNote([.skippedAmbiguous]) == "Not minimized: more than one matching Teams window",
              "ambiguous note")
        XCTAssertTrue(minimizeNote([.skippedStale]) == "Not minimized: the Teams window changed", "stale note")
        XCTAssertTrue(minimizeNote([.skippedUnreadable]) == "Not minimized: couldn't read the Teams window",
              "unreadable note")
        XCTAssertTrue(minimizeNote([.failed(.cannotComplete)]) == "Not minimized: Teams did not respond",
              "failed or timed-out note")
        XCTAssertTrue(minimizeNote([.minimized, .skippedStale, .failed(.failure)]) == "Not minimized: Teams did not respond",
              "a mixed result reports the failure")
        XCTAssertTrue(minimizeNote([.cancelled]) == nil, "a cancelled write adds no note")
    }

    func testPrefs() {
        // An absolute suite path keeps the throwaway settings file out of
        // ~/Library/Preferences.
        let suiteName = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindspot-tests-\(UUID().uuidString)").path
        let realStore = Prefs.store
        Prefs.store = UserDefaults(suiteName: suiteName)!
        XCTAssertTrue(!Prefs.autoMinimize, "minimizing is off when no choice is stored")
        Prefs.autoMinimize = true
        XCTAssertTrue(Prefs.autoMinimize, "a stored choice to minimize is kept")
        Prefs.autoMinimize = false
        XCTAssertTrue(!Prefs.autoMinimize, "a stored choice not to minimize is kept")
        XCTAssertTrue(!Prefs.screenRecordingRequested, "Screen Recording has not been requested in fresh settings")
        Prefs.store.removePersistentDomain(forName: suiteName)
        Prefs.store = realStore
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }

    func testSetup() {
        XCTAssertTrue(shouldOpenSetupAtLaunch(screenGranted: false, screenRequested: false),
              "first launch without Screen Recording opens setup")
        XCTAssertTrue(!shouldOpenSetupAtLaunch(screenGranted: false, screenRequested: true),
              "a launch after the prompt was shown does not open setup again")
        XCTAssertTrue(!shouldOpenSetupAtLaunch(screenGranted: true, screenRequested: false),
              "a launch with Screen Recording allowed does not open setup")
        XCTAssertTrue(screenRecordingAction(granted: false, requested: false) == .request,
              "the setup button asks macOS the first time")
        XCTAssertTrue(screenRecordingAction(granted: false, requested: true) == .openSettings,
              "after the prompt was shown the button opens System Settings")
        XCTAssertTrue(screenRecordingAction(granted: true, requested: false) == .openSettings,
              "with access allowed the button opens System Settings")
        XCTAssertTrue(screenRecordingHint(granted: false, requested: true) == "If you already allowed it, quit and reopen Blindspot.",
              "relaunch hint after the prompt without access")
        XCTAssertTrue(screenRecordingHint(granted: false, requested: false) == nil, "no relaunch hint before the prompt")
        XCTAssertTrue(screenRecordingHint(granted: true, requested: true) == nil, "no relaunch hint once allowed")
    }

    func testAccessibilityNote() {
        let accessibilityText = "Not minimized: needs Accessibility permission"
        XCTAssertTrue(accessibilityNote(displayShare, autoMinimize: true, trusted: false) == accessibilityText,
              "minimizing on without Accessibility explains why nothing was minimized")
        XCTAssertTrue(accessibilityNote(displayShare, autoMinimize: false, trusted: false) == nil,
              "no Accessibility note when minimizing is off")
        XCTAssertTrue(accessibilityNote(displayShare, autoMinimize: true, trusted: true) == nil,
              "no Accessibility note when trusted")
        XCTAssertTrue(accessibilityNote(windowShare, autoMinimize: true, trusted: false) == nil,
              "no Accessibility note for a window share")
        XCTAssertTrue(accessibilityNote(.paused, autoMinimize: true, trusted: false) == nil,
              "no Accessibility note while paused")
    }

    func testPreviewPlacement() {
        XCTAssertTrue(previewPlacement(state: .notSharing, windows: [indicator, chat], permission: true) == .sharing,
              "test warning is not shown during a Teams share")
        XCTAssertTrue(previewPlacement(state: .notSharing, windows: [chat], permission: true) == .anyScreen,
              "test warning can use any screen when nothing is shared")
        XCTAssertTrue(previewPlacement(state: .notSharing, windows: nil, permission: true) == .unknown,
              "test warning is hidden when windows cannot be read")
        XCTAssertTrue(previewPlacement(state: .notSharing, windows: [indicator], permission: false) == .unknown,
              "test warning is hidden without Screen Recording")
        XCTAssertTrue(previewPlacement(state: .notSharing, windows: [otherIndicator], permission: true) == .anyScreen,
              "another app's indicator does not count as a share for the test warning")
        XCTAssertTrue(previewPlacement(state: .paused, windows: [chat], permission: true) == .checksOff,
              "test warning is not shown while paused, since a new share would not hide it")
        XCTAssertTrue(previewPlacement(state: .checksDisabled, windows: [chat], permission: true) == .checksOff,
              "test warning is not shown while checks are disabled")
        XCTAssertTrue(previewPlacement(state: nil, windows: [chat], permission: true) == .unknown,
              "test warning is not shown before the first check")
    }

    func testLoginItem() {
        let realAgents = LoginItem.agentsDirectory
        let realExecutable = LoginItem.executablePath
        let realLaunchctl = LoginItem.runLaunchctl
        let loginRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindspot-login-tests-\(UUID().uuidString)")
        let agents = loginRoot.appendingPathComponent("Launch Agents")
        let appPath = "/Applications/My Apps/Blindspot.app/Contents/MacOS/Blindspot"
        LoginItem.agentsDirectory = agents
        LoginItem.executablePath = appPath
        var launchctlCalls: [[String]] = []
        var queryResult = LaunchctlResult(status: 0, output: "")
        var changeStatus: Int32? = 0
        LoginItem.runLaunchctl = { args in
            launchctlCalls.append(args)
            return args.first == "print-disabled" ? queryResult : LaunchctlResult(status: changeStatus, output: "")
        }
        let label = launchAgentLabel
        func writeAgent(_ program: String) {
            try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["Label": label, "ProgramArguments": [program], "RunAtLoad": true,
                                        "KeepAlive": ["SuccessfulExit": false], "ProcessType": "Interactive"]
            let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try! data.write(to: LoginItem.plistURL)
        }
        func readAgent() -> [String: Any]? {
            guard let data = try? Data(contentsOf: LoginItem.plistURL) else { return nil }
            return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        }

        XCTAssertTrue(LoginItem.isEnabled == false && launchctlCalls.isEmpty, "no login item when the plist is absent")
        writeAgent(appPath)
        XCTAssertTrue(LoginItem.isEnabled == true, "a current login item with no disabled entry is enabled")
        queryResult = LaunchctlResult(status: 0, output: "\t\"\(label)\" => disabled\n")
        XCTAssertTrue(LoginItem.isEnabled == false, "a disabled entry is not enabled")
        queryResult = LaunchctlResult(status: 0, output: "\t\"\(label)\" => true\n")
        XCTAssertTrue(LoginItem.isEnabled == false, "the older disabled wording is not enabled")
        queryResult = LaunchctlResult(status: 1, output: "")
        XCTAssertTrue(LoginItem.isEnabled == nil, "a failed launchctl query is unknown, not enabled")
        queryResult = LaunchctlResult(status: nil, output: "")
        XCTAssertTrue(LoginItem.isEnabled == nil, "launchctl that cannot start is unknown, not enabled")
        queryResult = LaunchctlResult(status: 0, output: "")

        writeAgent("/Old Place/Blindspot.app/Contents/MacOS/Blindspot")
        XCTAssertTrue(LoginItem.isEnabled == false && LoginItem.isStale, "a login item for an old copy is not enabled")
        launchctlCalls = []
        XCTAssertTrue(LoginItem.setEnabled(true) == nil, "enabling an old login item succeeds")
        let repaired = readAgent()
        XCTAssertTrue(repaired?["ProgramArguments"] as? [String] == [appPath],
              "enabling repairs the path, with spaces kept in one argument")
        XCTAssertTrue(repaired?["Label"] as? String == label && repaired?["RunAtLoad"] as? Bool == true
              && (repaired?["KeepAlive"] as? [String: Bool]) == ["SuccessfulExit": false]
              && repaired?["ProcessType"] as? String == "Interactive",
              "repair keeps the label, RunAtLoad, KeepAlive and ProcessType")
        XCTAssertTrue(launchctlCalls == [["enable", "\(LoginItem.domain)/\(label)"]],
              "enabling runs only launchctl enable for this label")
        XCTAssertTrue(!LoginItem.isStale && LoginItem.isEnabled == true, "a repaired login item is enabled")

        let unrelated = agents.appendingPathComponent("com.example.other.plist")
        try? Data("unrelated".utf8).write(to: unrelated)
        launchctlCalls = []
        changeStatus = 1
        XCTAssertTrue(LoginItem.setEnabled(true) == "Couldn't turn on Start at Login.", "a failed enable is reported")
        XCTAssertTrue(LoginItem.setEnabled(false) == "Couldn't turn off Start at Login.", "a failed disable is reported")
        changeStatus = 0
        let beforeDisable = try? Data(contentsOf: LoginItem.plistURL)
        XCTAssertTrue(LoginItem.setEnabled(false) == nil, "a successful disable reports no problem")
        XCTAssertTrue((try? Data(contentsOf: LoginItem.plistURL)) == beforeDisable, "disabling leaves the plist alone")
        XCTAssertTrue((try? String(contentsOf: unrelated, encoding: .utf8)) == "unrelated", "unrelated login items are untouched")
        XCTAssertTrue(launchctlCalls.allSatisfy { $0.last == "\(LoginItem.domain)/\(label)" },
              "launchctl changes only ever name this label")

        try? FileManager.default.removeItem(at: LoginItem.plistURL)
        launchctlCalls = []
        XCTAssertTrue(LoginItem.setEnabled(true) == nil && readAgent()?["ProgramArguments"] as? [String] == [appPath],
              "enabling with no plist writes one")
        XCTAssertTrue(launchctlCalls.count == 1, "enabling with no plist then runs enable")

        try? FileManager.default.removeItem(at: agents)
        try? Data().write(to: agents)
        launchctlCalls = []
        XCTAssertTrue(LoginItem.setEnabled(true) == "Couldn't save the login item.", "a failed write is reported")
        XCTAssertTrue(launchctlCalls.isEmpty, "a failed write does not run launchctl")

        try? FileManager.default.removeItem(at: loginRoot)
        LoginItem.agentsDirectory = realAgents
        LoginItem.executablePath = realExecutable
        LoginItem.runLaunchctl = realLaunchctl
    }
}
