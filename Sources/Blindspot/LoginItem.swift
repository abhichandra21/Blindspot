import AppKit

let launchAgentLabel = "com.abhichandra.blindspot"

// Start at login is the launchd agent in ~/Library/LaunchAgents. Turning it off
// uses `launchctl disable`, which stops future logins from starting it without
// killing the copy that is running now.
struct LaunchctlResult {
    // nil when launchctl could not be started at all.
    let status: Int32?
    let output: String
}

enum LoginItem {
    // Tests swap these for a temporary folder, a fake app path and a fake
    // launchctl, so they never touch the real login entry.
    static var agentsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    static var executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
    static var runLaunchctl: ([String]) -> LaunchctlResult = launchctl

    static var plistURL: URL { agentsDirectory.appendingPathComponent("\(launchAgentLabel).plist") }
    static var domain: String { "gui/\(getuid())" }

    // The plist exists but would not start this copy, e.g. after the app moved.
    static var isStale: Bool {
        FileManager.default.fileExists(atPath: plistURL.path) && !pointsAtThisCopy
    }

    private static var pointsAtThisCopy: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let program = plist["ProgramArguments"] as? [String] else { return false }
        return program.first == executablePath
    }

    // nil when launchctl could not answer; that is not proof either way.
    static var isEnabled: Bool? {
        guard pointsAtThisCopy else { return false }
        let result = runLaunchctl(["print-disabled", domain])
        guard result.status == 0 else {
            NSLog("Failed to check Start at Login: launchctl status \(result.status.map(String.init) ?? "not run")")
            return nil
        }
        let disabled = result.output.split(separator: "\n").contains { line in
            // Lines look like: "label" => disabled   (older macOS: => true)
            line.contains("\"\(launchAgentLabel)\"") && (line.contains("=> disabled") || line.contains("=> true"))
        }
        return !disabled
    }

    // Returns a short reason when the change failed, or nil.
    static func setEnabled(_ enabled: Bool) -> String? {
        if enabled && !pointsAtThisCopy && !writePlist() {
            return "Couldn't save the login item."
        }
        let result = runLaunchctl([enabled ? "enable" : "disable", "\(domain)/\(launchAgentLabel)"])
        guard result.status == 0 else {
            NSLog("Failed to change Start at Login: launchctl status \(result.status.map(String.init) ?? "not run")")
            return enabled ? "Couldn't turn on Start at Login." : "Couldn't turn off Start at Login."
        }
        return nil
    }

    private static func writePlist() -> Bool {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            // Restart after a crash, but not after Quit from the menu (clean exit).
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            return true
        } catch {
            NSLog("Failed to write launch agent \(plistURL.path): \(error)")
            return false
        }
    }

    private static func launchctl(_ args: [String]) -> LaunchctlResult {
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
            return LaunchctlResult(status: nil, output: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return LaunchctlResult(status: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
