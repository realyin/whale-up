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
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_RENDER_STATS"] {
        // 用示例数据画统计页
        var stats = UsageStats()
        let samples: [(String, [Double])] = [
            ("site:bilibili.com", [35, 52, 18, 64, 41, 12, 39]), ("site:douyin.com", [20, 8, 30, 15, 0, 25, 12]),
            ("site:zhihu.com", [15, 20, 10, 5, 12, 8, 22]), ("app:Xcode", [120, 90, 0, 150, 200, 60, 180]),
            ("site:github.com", [40, 30, 0, 50, 60, 20, 45]), ("app:微信", [30, 25, 40, 20, 35, 50, 28]),
        ]
        for (key, minutes) in samples {
            for (i, m) in minutes.enumerated() {
                stats.add(key, seconds: m * 60, at: Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!)
            }
        }
        let model = StatsModel(stats: stats, config: Config())
        StatsWindow.renderPNG(model: model, junkOnly: true, to: URL(fileURLWithPath: dir).appendingPathComponent("stats-junk.png"))
        StatsWindow.renderPNG(model: model, junkOnly: false, to: URL(fileURLWithPath: dir).appendingPathComponent("stats-all.png"))
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
