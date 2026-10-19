import AppKit
import FocusGuardCore

MainActor.assumeIsolated {
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_RENDER_NUDGE"] {
        for night in [false, true] {
            let n = Nudge(reason: "douyin.com", appName: "Safari", sessionMinutes: 20, todayMinutes: 47, isNight: night, count: 1)
            NudgeWindow.renderPNG(Messages.make(for: n), isNight: night,
                                  to: URL(fileURLWithPath: dir).appendingPathComponent(night ? "nudge-night.png" : "nudge-day.png"))
        }
        exit(0)
    }
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_RENDER_SETTINGS"] {
        let model = SettingsModel(config: Config.load().0) { _ in }
        model.browserURL = "https://www.zhihu.com/question/123"
        for tab in SettingsTab.allCases {
            SettingsWindow.renderPNG(model: model, tab: tab,
                                     to: URL(fileURLWithPath: dir).appendingPathComponent("settings-\(tab).png"))
        }
        exit(0)
    }
    if let id = ProcessInfo.processInfo.environment["FOCUSGUARD_CLOSE_JUNK"] {
        print("closed:", ActivityMonitor().closeJunk(bundleID: id, nudgedURL: nil, rules: Config.load().0.junkSites))
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 只在菜单栏显示，不出现在程序坞
    app.setActivationPolicy(.accessory)
    app.run()
}
