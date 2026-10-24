import AppKit

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
