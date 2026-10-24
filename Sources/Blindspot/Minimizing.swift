import AppKit

// Bounds each Accessibility call (the macOS default is about 6 seconds).
let axMessagingTimeoutSeconds: Float = 1.0

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
    // No longer wanted by the time of the write, e.g. after a pause.
    case cancelled
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
// stillWanted is checked right before each write, so a pause or the share
// ending stops writes that have not been sent yet.
@discardableResult
func minimize(_ windows: [WindowInfo], stillWanted: () -> Bool = { true }) -> [MinimizeOutcome] {
    var outcomes: [MinimizeOutcome] = []
    for (pid, group) in Dictionary(grouping: windows, by: \.pid) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard readResult == .success, let axWindows = value as? [AXUIElement] else {
            let error = readResult == .success ? AXError.failure : readResult
            outcomes += group.map { _ in .failed(error) }
            continue
        }
        let candidates = axWindows.map(axCandidate)
        for target in group {
            switch matchAXWindow(target, in: candidates) {
            case .match(let index):
                guard stillWanted() else {
                    outcomes.append(.cancelled)
                    continue
                }
                let result = AXUIElementSetAttributeValue(axWindows[index], kAXMinimizedAttribute as CFString,
                                                          kCFBooleanTrue)
                outcomes.append(result == .success ? .minimized : .failed(result))
            case .ambiguous: outcomes.append(.skippedAmbiguous)
            case .stale: outcomes.append(.skippedStale)
            case .unreadable: outcomes.append(.skippedUnreadable)
            }
        }
    }
    return outcomes
}

// Retry every tick while exposed, so it still works once permission is granted.
func minimizeAttemptTargets(_ state: GuardState, autoMinimize: Bool, trusted: Bool) -> [WindowInfo] {
    autoMinimize && trusted ? state.autoMinimizeTargets : []
}

// A short reason shown under the warning when minimizing did not happen;
// nil when every attempted window was minimized. A failure wins over a skip.
func minimizeNote(_ outcomes: [MinimizeOutcome]) -> String? {
    if outcomes.contains(where: { if case .failed = $0 { return true } else { return false } }) {
        return "Not minimized: Teams did not respond"
    }
    if outcomes.contains(.skippedUnreadable) { return "Not minimized: couldn't read the Teams window" }
    if outcomes.contains(.skippedAmbiguous) { return "Not minimized: more than one matching Teams window" }
    if outcomes.contains(.skippedStale) { return "Not minimized: the Teams window changed" }
    return nil
}

// Runs one minimize attempt at a time off the main thread, so the warning is
// never held up by a slow Teams. Used only from the main thread, except the
// generation check the running attempt makes before each write.
final class MinimizeAttempts {
    private let perform: ([WindowInfo], @escaping () -> Bool) -> [MinimizeOutcome]
    private let runAsync: (@escaping () -> Void) -> Void
    private let deliver: (@escaping () -> Void) -> Void
    private var inFlight = false
    private let generationLock = NSLock()
    private var generation = 0

    private var currentGeneration: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    init(perform: @escaping ([WindowInfo], @escaping () -> Bool) -> [MinimizeOutcome] = { minimize($0, stillWanted: $1) },
         runAsync: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
         deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.perform = perform
        self.runAsync = runAsync
        self.deliver = deliver
    }

    // Does nothing while an attempt is still running, including a cancelled one.
    func start(_ targets: [WindowInfo], completion: @escaping ([MinimizeOutcome]) -> Void) {
        guard !inFlight else { return }
        inFlight = true
        let startedGeneration = currentGeneration
        let perform = self.perform
        let deliver = self.deliver
        runAsync { [weak self] in
            let outcomes = perform(targets, { self?.currentGeneration == startedGeneration })
            deliver {
                guard let self else { return }
                self.inFlight = false
                if startedGeneration == self.currentGeneration { completion(outcomes) }
            }
        }
    }

    // Stops the running attempt's remaining writes and drops its result, e.g.
    // after a pause or the share ending. An Accessibility call already sent
    // still finishes within the messaging timeout.
    func cancel() {
        generationLock.lock()
        generation += 1
        generationLock.unlock()
    }
}

func accessibilityNote(_ state: GuardState, autoMinimize: Bool, trusted: Bool) -> String? {
    autoMinimize && !trusted && !state.autoMinimizeTargets.isEmpty
        ? "Not minimized: needs Accessibility permission" : nil
}

// Shows the macOS prompt that sends the user to the Accessibility list.
func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}
