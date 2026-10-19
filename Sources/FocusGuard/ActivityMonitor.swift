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

    /// 关掉正在看的“没营养”页面：浏览器里只关当前这一个标签页，其他 App 直接退出。
    /// nudgedURL 是弹窗出现时的网址；短视频网站划走后网址会变，所以优先看当前标签页。
    @discardableResult
    func closeJunk(bundleID: String, nudgedURL: String?, config: Config) -> Bool {
        guard let browser = Self.browserNames[bundleID] else {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            return true
        }
        let current = bundleID == "com.apple.Safari" ? "current tab" : "active tab"

        // 1. 当前标签页还在没营养的网站上 → 关掉它
        let active = run("""
            tell application "\(browser)"
                if (count of windows) is 0 then return ""
                return URL of \(current) of front window
            end tell
            """)
        if let url = active, Classifier.junkSite(for: url, config: config) != nil {
            return run("""
                tell application "\(browser)"
                    set w to front window
                    \(Self.closeOrBlank("\(current) of w"))
                end tell
                return "ok"
                """) != nil
        }

        // 2. 用户已经切到别的标签页 → 按弹窗时的网址找到那一个关掉
        guard let target = nudgedURL else { return false }
        let quoted = "\"" + target.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return run("""
            tell application "\(browser)"
                repeat with w in (every window)
                    try
                        repeat with t in (every tab of w)
                            if (URL of t as text) is \(quoted) then
                                \(Self.closeOrBlank("t"))
                                return "ok"
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            return "notfound"
            """) == "ok"
    }

    /// 窗口里只剩这一个标签页时改成空白页，避免整个窗口被关掉
    private static func closeOrBlank(_ tab: String) -> String {
        """
        if (count of tabs of w) is 1 then
            set URL of \(tab) to "about:blank"
        else
            close \(tab)
        end if
        """
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("FocusGuard: AppleScript 出错 %@", error)
            return nil
        }
        return result?.stringValue
    }

    /// 距离最后一次键盘/鼠标操作的秒数
    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
