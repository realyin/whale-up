import AppKit
import FocusGuardCore

/// 读取系统状态：前台 App、浏览器当前网址、键鼠空闲时长。
@MainActor
final class ActivityMonitor {
    /// 浏览器 Bundle ID → 读取当前标签页“网址\n标题”的 AppleScript
    private static let browserSources: [String: String] = {
        func chromium(_ name: String) -> String {
            """
            tell application "\(name)"
                if (count of windows) is 0 then return ""
                return (URL of active tab of front window) & linefeed & (title of active tab of front window)
            end tell
            """
        }
        return [
            "com.apple.Safari": """
                tell application "Safari"
                    if (count of windows) is 0 then return ""
                    return (URL of current tab of front window) & linefeed & (name of current tab of front window)
                end tell
                """,
            "com.google.Chrome": chromium("Google Chrome"),
            "com.microsoft.edgemac": chromium("Microsoft Edge"),
            "com.brave.Browser": chromium("Brave Browser"),
            "company.thebrowser.Browser": chromium("Arc"),
        ]
    }()

    private var scripts: [String: NSAppleScript] = [:]
    /// 没有获得“自动化”授权、无法读取网址的浏览器名称
    private(set) var deniedBrowsers: Set<String> = []

    func currentActivity() -> Activity? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = app.localizedName ?? app.bundleIdentifier ?? "未知应用"
        var activity = Activity(appName: name, bundleID: app.bundleIdentifier)

        if let id = app.bundleIdentifier, let source = Self.browserSources[id] {
            let script = scripts[id] ?? NSAppleScript(source: source)!
            scripts[id] = script
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                // -1743：用户未允许本应用控制该浏览器
                if (error[NSAppleScript.errorNumber] as? Int) == -1743 { deniedBrowsers.insert(name) }
            } else {
                deniedBrowsers.remove(name)
                let lines = (result.stringValue ?? "").components(separatedBy: "\n")
                activity.url = lines.first.flatMap { $0.isEmpty ? nil : $0 }
                activity.title = lines.count > 1 ? lines[1] : nil
            }
        }
        return activity
    }

    private static let browserNames: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave Browser",
        "company.thebrowser.Browser": "Arc",
    ]

    /// 关掉“没营养”的内容：浏览器里关掉所有命中规则的标签页，其他 App 直接退出。
    /// 返回关掉的标签页数量（退出 App 时为 0）。
    @discardableResult
    func closeJunk(bundleID: String, config: Config) -> Int {
        guard let browser = Self.browserNames[bundleID] else {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            return 0
        }

        let junkURLs = junkTabURLs(browser: browser, config: config)
        guard !junkURLs.isEmpty else { return 0 }

        let list = junkURLs.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: ", ")
        let close = """
            set junkList to {\(list)}
            tell application "\(browser)"
                repeat with w in (every window)
                    try
                        set ts to tabs of w
                        repeat with i from (count of ts) to 1 by -1
                            try
                                if junkList contains (URL of item i of ts as text) then close item i of ts
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: close)?.executeAndReturnError(&error)
        if let error { NSLog("FocusGuard: 关闭 %@ 标签页失败 %@", browser, error) }
        return error == nil ? junkURLs.count : 0
    }

    /// 浏览器里所有命中规则的标签页网址。在 Swift 里按规则精确匹配，避免误关 box.com 这类相似域名。
    func junkTabURLs(browser: String, config: Config) -> [String] {
        // 逐个窗口、逐个标签页取，某个窗口出错（比如没有标签页）不影响其他窗口
        let source = """
            set out to ""
            tell application "\(browser)"
                repeat with w in (every window)
                    try
                        repeat with t in (every tab of w)
                            try
                                set out to out & (URL of t) & linefeed
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            return out
            """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("FocusGuard: 读取 %@ 标签页失败 %@", browser, error) }
        return (result?.stringValue ?? "").components(separatedBy: "\n")
            .filter { Classifier.junkSite(for: $0, config: config) != nil }
    }

    /// 距离最后一次键盘/鼠标操作的秒数
    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
