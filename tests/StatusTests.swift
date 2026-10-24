import CoreGraphics

struct StatusTests {
    static func main() {
        var checks = 0
        var failures = 0

        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if condition {
                print("PASS: \(name)")
            } else {
                failures += 1
                print("FAIL: \(name)")
            }
        }

        func checkText(_ state: GuardState, _ expected: String, _ name: String) {
            check(state.statusText == expected, "\(name): expected '\(expected)', got '\(state.statusText)'")
        }

        func window(_ title: String, _ bounds: CGRect, owner: String = teamsOwnerPrefix,
                    layer: Int = 0) -> WindowInfo {
            WindowInfo(owner: owner, pid: 123, title: title, layer: layer, bounds: bounds)
        }

        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let indicator = window(sharingIndicatorTitle, display)
        let chat = window("Chat | Synthetic", CGRect(x: 1100, y: 100, width: 300, height: 300))
        let outside = window("Chat | Synthetic", CGRect(x: 1400, y: 100, width: 300, height: 300))
        let clearText = "Sharing; no watched Teams windows detected in the shared area"
        let disabledText = "Checks disabled: no Teams tabs selected"
        let failureText = "Unable to check Teams sharing"

        func detect(_ windows: [WindowInfo]?, tabs: [String] = allRiskyTabs,
                    permission: Bool = true, paused: Bool = false,
                    displays: [CGRect]? = nil) -> GuardState {
            currentState(paused: paused, riskyTabs: tabs, hasPermission: { permission },
                         readWindows: { windows }, readDisplays: { displays ?? [display] })
        }

        checkText(detect([indicator, chat], tabs: []), disabledText,
                  "no selected tabs must not report a clear share")
        checkText(detect(nil), failureText, "failed window observation must not report no share")
        checkText(detect([]), "No Teams share detected", "valid empty window list")
        checkText(detect([chat]), "No Teams share detected", "no matching share indicator")
        checkText(detect([indicator, outside]), clearText, "watched window outside the shared area")
        checkText(detect([indicator]), clearText, "share without a watched window")

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

        check(observed(paused: true, tabs: [], permission: false) == .paused,
              "pause takes precedence over disabled checks, permission and failed observation")
        check(permissionReads == 0 && windowReads == 0 && displayReads == 0,
              "paused checks do not observe permission, windows or displays")
        checkText(observed(tabs: [], permission: false), disabledText,
                  "disabled checks take precedence over missing permission")
        check(permissionReads == 0 && windowReads == 0 && displayReads == 0,
              "disabled checks do not observe permission, windows or displays")
        permissionReads = 0
        windowReads = 0
        displayReads = 0
        check(observed(permission: false) == .noPermission,
              "permission denial takes precedence over failed window observation")
        check(permissionReads == 1 && windowReads == 0 && displayReads == 0,
              "permission denial does not read windows or displays")
        checkText(observed(), failureText, "failed window observation with checks enabled")
        check(displayReads == 0, "failed window observation does not read displays")
        checkText(observed(windows: []), "No Teams share detected",
                  "no share result does not require display observation")
        check(displayReads == 0, "no share does not read displays")
        checkText(observed(windows: [indicator, chat]), failureText,
                  "failed display observation must not classify a detected share")
        check(displayReads == 1, "detected share reads display observation")

        checkText(detect([], permission: false), "Needs Screen Recording permission",
                  "permission status wording is preserved")
        checkText(detect([], paused: true), "Paused", "pause status wording is preserved")
        checkText(detect([indicator, chat]), "Teams Chat may be visible in your share",
                  "warning status wording is preserved")
        check(detect([indicator, chat]) == .chatExposed([chat], display, wholeDisplay: true),
              "partial display exposure remains a warning")
        let coveringWindow = window("Synthetic cover", display, owner: "Other App")
        check(detect([coveringWindow, indicator, chat]) == .chatExposed([chat], display, wholeDisplay: true),
              "a watched window behind another app still counts")
        let activity = window("Activity | Synthetic", chat.bounds)
        check(detect([indicator, activity], tabs: ["Activity"]) == .chatExposed([activity], display, wholeDisplay: true),
              "selected Activity tab remains watched")
        check(detect([indicator, chat], tabs: ["Activity"]) == .sharingClear,
              "unselected Chat tab does not trigger exposure")
        let otherIndicator = window(sharingIndicatorTitle, display, owner: "Other App")
        check(detect([otherIndicator, chat]) == .notSharing,
              "another app's indicator does not count as a Teams share")
        let otherChat = window("Chat | Synthetic", chat.bounds, owner: "Other App")
        check(detect([indicator, otherChat]) == .sharingClear,
              "another app's Chat title does not count as a watched window")
        let nonstandardLayer = window("Chat | Synthetic", chat.bounds, layer: 1)
        check(detect([indicator, nonstandardLayer]) == .sharingClear,
              "existing window layer filter is preserved")

        let sharedWindow = CGRect(x: 100, y: 100, width: 400, height: 400)
        let windowIndicator = window(sharingIndicatorTitle, sharedWindow)
        let halfOverlap = window("Chat | Synthetic", CGRect(x: 300, y: 100, width: 400, height: 400))
        let lessOverlap = window("Chat | Synthetic", CGRect(x: 301, y: 100, width: 400, height: 400))
        check(detect([windowIndicator, halfOverlap]) == .chatExposed([halfOverlap], sharedWindow, wholeDisplay: false),
              "existing window-share 50 percent threshold is preserved")
        check(detect([windowIndicator, lessOverlap]) == .sharingClear,
              "existing window-share below-threshold result is preserved")

        check(detect([indicator, chat]).autoMinimizeTargets == [chat],
              "display share with partial Chat overlap may be minimized")
        let secondDisplay = CGRect(x: 1200, y: 0, width: 1200, height: 800)
        let chatOnSecond = window("Chat | Synthetic", CGRect(x: 1400, y: 100, width: 300, height: 300))
        check(detect([indicator, chatOnSecond], displays: [display, secondDisplay]) == .sharingClear,
              "Chat on another display does not warn")
        let presentation = CGRect(x: 100, y: 100, width: 600, height: 400)
        let presentationIndicator = window(sharingIndicatorTitle, presentation)
        let chatBehind = window("Chat | Synthetic", presentation)
        let windowShare = detect([presentationIndicator, chatBehind])
        check(windowShare == .chatExposed([chatBehind], presentation, wholeDisplay: false),
              "Chat behind a shared presentation window still warns")
        check(windowShare.autoMinimizeTargets.isEmpty,
              "window share is not automatically minimized")
        check(GuardState.sharingClear.autoMinimizeTargets.isEmpty, "clear share has nothing to minimize")

        let target = window("Chat | Synthetic", CGRect(x: 100, y: 100, width: 300, height: 300))
        let elsewhere = CGRect(x: 500, y: 100, width: 300, height: 300)
        func candidate(_ title: String?, _ frame: CGRect?) -> AXWindowCandidate {
            AXWindowCandidate(title: title, frame: frame)
        }
        check(matchAXWindow(target, in: [candidate("Chat | Synthetic", elsewhere),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "same-title AX windows are told apart by position")
        let rounded = target.bounds.offsetBy(dx: 0.5, dy: -0.5)
        check(matchAXWindow(target, in: [candidate("Chat | Synthetic", rounded)]) == .match(0),
              "sub-point rounding still matches")
        check(matchAXWindow(target, in: [candidate("Chat | Synthetic", target.bounds),
                                         candidate("Chat | Synthetic", target.bounds)]) == .ambiguous,
              "two indistinguishable AX windows are ambiguous")
        check(matchAXWindow(target, in: [candidate("Chat | Synthetic", elsewhere)]) == .stale,
              "a moved window is stale")
        check(matchAXWindow(target, in: [candidate("Calendar | Synthetic", target.bounds)]) == .stale,
              "a retitled window is stale")
        check(matchAXWindow(target, in: [candidate(nil, target.bounds)]) == .unreadable,
              "an unreadable title is not guessed")
        check(matchAXWindow(target, in: [candidate("Chat | Synthetic", nil)]) == .unreadable,
              "an unreadable frame is not guessed")
        check(matchAXWindow(target, in: [candidate("Calendar | Synthetic", nil),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "an unreadable frame on another title does not block a clear match")
        check(matchAXWindow(target, in: [candidate(nil, elsewhere),
                                         candidate("Chat | Synthetic", target.bounds)]) == .match(1),
              "an untitled window elsewhere does not block a clear match")
        check(matchAXWindow(target, in: [candidate(nil, nil)]) == .unreadable,
              "an untitled window with no frame is not guessed")

        let displayShare = detect([indicator, chat])
        check(minimizeAttemptTargets(displayShare, autoMinimize: true, trusted: true) == [chat],
              "display share with minimizing on is attempted")
        check(minimizeAttemptTargets(displayShare, autoMinimize: false, trusted: true).isEmpty,
              "no attempt when minimizing is off")
        check(minimizeAttemptTargets(displayShare, autoMinimize: true, trusted: false).isEmpty,
              "no attempt without Accessibility trust")
        check(minimizeAttemptTargets(windowShare, autoMinimize: true, trusted: true).isEmpty,
              "no attempt for a window share")
        check(minimizeAttemptTargets(.paused, autoMinimize: true, trusted: true).isEmpty,
              "no attempt while paused")

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
        check(performed == 0 && delivered.isEmpty, "starting an attempt does not run it on the caller")
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        check(performed == 1 && delivered == [[.failed(.cannotComplete)]],
              "only one attempt runs while one is in flight")
        nextOutcomes = [.minimized]
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        check(performed == 2 && delivered.last == [.minimized], "a failed attempt is retried on the next start")

        delivered = []
        attempts.start([chat]) { delivered.append($0) }
        attempts.cancel()
        attempts.start([chat]) { delivered.append($0) }
        check(background.count <= 1, "cancel does not allow a second attempt while the first runs")
        runPending()
        check(performed == 3, "cancel and restart before the old attempt finishes runs it only once")
        check(delivered.isEmpty, "a cancelled attempt's result is dropped")
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        check(performed == 4 && delivered == [[.minimized]], "after the cancelled attempt finishes, a new one runs")
        check(writes == 3, "an attempt cancelled before it runs makes no write")

        delivered = []
        betweenReadAndWrite = { attempts.cancel() }
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        check(performed == 5 && writes == 3, "a cancel between reading and writing stops the write")
        check(delivered.isEmpty, "a cancel between reading and writing drops the result")
        betweenReadAndWrite = {}
        attempts.start([chat]) { delivered.append($0) }
        runPending()
        check(writes == 4 && delivered == [[.minimized]], "the next attempt after that cancel writes")

        check(minimizeNote([]) == nil, "no note when nothing was attempted")
        check(minimizeNote([.minimized, .minimized]) == nil, "no note when everything was minimized")
        check(minimizeNote([.skippedAmbiguous]) == "Not minimized: more than one matching Teams window",
              "ambiguous note")
        check(minimizeNote([.skippedStale]) == "Not minimized: the Teams window changed", "stale note")
        check(minimizeNote([.skippedUnreadable]) == "Not minimized: couldn't read the Teams window",
              "unreadable note")
        check(minimizeNote([.failed(.cannotComplete)]) == "Not minimized: Teams did not respond",
              "failed or timed-out note")
        check(minimizeNote([.minimized, .skippedStale, .failed(.failure)]) == "Not minimized: Teams did not respond",
              "a mixed result reports the failure")
        check(minimizeNote([.cancelled]) == nil, "a cancelled write adds no note")

        print("\(checks - failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }
}
