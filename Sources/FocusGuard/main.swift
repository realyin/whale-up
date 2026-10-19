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
    if ProcessInfo.processInfo.environment["FOCUSGUARD_WRITE_DIGEST"] != nil, let store = try? ContentStore() {
        // 开发用：立刻写今天的小结并打印
        let writer = DigestWriter(store: store)
        Task {
            do { print(try await writer.write(day: Date(), config: Config.load().0).text) } catch { print("失败：\(error)") }
            exit(0)
        }
        RunLoop.main.run()
    }
    if ProcessInfo.processInfo.environment["FOCUSGUARD_TEST_LABEL"] != nil {
        // 开发用：用当前配置判断两条示例
        Task {
            for v in Labeler.samples {
                do { print(v.title, "→", try await Labeler.classify(v, llm: Config.load().0.llm)) } catch { print("失败：\(error)") }
            }
            exit(0)
        }
        RunLoop.main.run()
    }
    if ProcessInfo.processInfo.environment["FOCUSGUARD_TEST_NUDGE"] != nil, let store = try? ContentStore() {
        // 开发用：按最近 2 小时的记录写一条劝导文案
        Task {
            let llm = Config.load().0.llm
            let now = Date()
            let recent = (try? store.views(from: now.addingTimeInterval(-7200), to: now)) ?? []
            let p = NudgePrompt.make(nudge: Nudge(reason: "youtube.com", appName: "Chrome", sessionMinutes: 25, todayMinutes: 60,
                                                  isNight: true, count: 1),
                                     recentViews: recent, reasons: [.tired], outcomes: nil, hourMinute: "00:40")
            let started = Date()
            do {
                let req = try LLMRequest.chat(NudgePrompt.spec(p, llm: llm), llm: llm, apiKey: APIKeyStore.get(llm.provider), timeout: 4)
                let (data, _) = try await URLSession.shared.data(for: req)
                print(try NudgePrompt.parse(data, provider: llm.provider), String(format: "%.1fs", Date().timeIntervalSince(started)))
            } catch { print("失败：\(error)", String(format: "%.1fs", Date().timeIntervalSince(started))) }
            exit(0)
        }
        RunLoop.main.run()
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
