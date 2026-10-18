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

    /// 距离最后一次键盘/鼠标操作的秒数
    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
