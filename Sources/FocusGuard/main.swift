import AppKit
import FocusGuardCore

MainActor.assumeIsolated {
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_RENDER_NUDGE"] {
        for night in [false, true] {
            let n = Nudge(reason: "douyin.com", appName: "Safari", sessionMinutes: 20, todayMinutes: 47, isNight: night, count: 1)
            NudgeWindow.renderPNG(Messages.make(for: n), isNight: night,
                                  to: URL(fileURLWithPath: dir).appendingPathComponent(night ? "nudge-night.png" : "nudge-day.png"))
        }
        let n3 = Nudge(reason: "douyin.com", appName: "Safari", sessionMinutes: 30, todayMinutes: 70, isNight: false, count: 3)
        NudgeWindow.renderPNG(Messages.make(for: n3), isNight: false, friction: .writeReason(waitSeconds: 10),
                              to: URL(fileURLWithPath: dir).appendingPathComponent("nudge-friction.png"))
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
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_RENDER_MAIN"] {
        renderMainDemo(to: dir)
        exit(0)
    }
    if ProcessInfo.processInfo.environment["FOCUSGUARD_WRITE_DIGEST"] != nil, let store = try? ContentStore() {
        // 开发用：立刻写今天的小结并打印
        let writer = DigestWriter(store: store)
        Task {
            do { print(try await writer.write(day: Date(), config: Config.load().0).daily?.markdown ?? "解析失败") } catch { print("失败：\(error)") }
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
    if ProcessInfo.processInfo.environment["FOCUSGUARD_WRITE_WEEKLY"] != nil, let store = try? ContentStore() {
        // 开发用：立刻写本周复盘并打印
        let writer = DigestWriter(store: store)
        Task {
            do {
                let config = Config.load().0
                print(try await writer.writeWeekly(week: Week(containing: Date()), config: config).weekly?.markdown ?? "解析失败")
                print("Obsidian：", DigestWriter.obsidianRoot(config)?.path ?? "未写入", writer.obsidianError ?? "")
            } catch { print("失败：\(error)") }
            exit(0)
        }
        RunLoop.main.run()
    }
    if let url = ProcessInfo.processInfo.environment["FOCUSGUARD_TEST_FAVORITE"] {
        // 开发用：在临时数据库里，按“从看过的内容收藏”的流程抓网页、提炼要点并打印
        let store = try! ContentStore(path: NSTemporaryDirectory() + "fg-favtest-\(UUID().uuidString).sqlite")
        let extractor = FavoriteExtractor(store: store)
        extractor.onChange = { done in
            guard let done else { return }
            print("根据\(done.textKind.label)（\(done.text.count) 字）：\(done.points?.markdown ?? "")")
            exit(0)
        }
        Task {
            let v = ContentView(viewId: "t", url: url, title: url, kind: "page", startedAt: 0, endedAt: 0, activeSeconds: 0)
            await extractor.saveFromHistory(v, config: Config.load().0)
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            print("失败：", (try? store.favorites().first?.error) ?? "超时")
            exit(1)
        }
        RunLoop.main.run()
    }
    if let dir = ProcessInfo.processInfo.environment["FOCUSGUARD_MASCOT_DEMO"] {
        runMascotDemo(to: dir)
        NSApplication.shared.run()
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

/// 开发用：用示例数据把主窗口每一页画成 PNG
@MainActor
func renderMainDemo(to dir: String) {
    // 用示例数据把主窗口每一页画成 PNG
    var config = Config()
    config.llm.enabled = true
    config.dailyBudgetMinutes = 60
    let store = try! ContentStore(path: NSTemporaryDirectory() + "fg-demo-\(UUID().uuidString).sqlite")
    var stats = UsageStats()
    let cal = Calendar.current
    struct Demo {
        var daysAgo: Int, hour: Int, minute: Int, site: String, title: String, author: String?
        var minutes: Double, junk: Bool, category: String, hook: String?
    }
    var demo = [
        Demo(daysAgo: 0, hour: 9, minute: 10, site: "bilibili.com", title: "Swift 并发编程入门：async/await 实战", author: "程序员小李", minutes: 18, junk: false, category: "技术", hook: nil),
        Demo(daysAgo: 0, hour: 12, minute: 30, site: "douyin.com", title: "这也太好笑了吧 #沙雕日常", author: "快乐小王", minutes: 1, junk: true, category: "搞笑", hook: "搞笑"),
        Demo(daysAgo: 0, hour: 12, minute: 31, site: "douyin.com", title: "猫咪的迷惑行为大赏 #萌宠", author: "猫奴日记", minutes: 1.5, junk: true, category: "萌宠", hook: "颜值"),
        Demo(daysAgo: 0, hour: 12, minute: 33, site: "douyin.com", title: "第275集：#末日求生 #末日生存", author: "小白.", minutes: 3, junk: true, category: "影视", hook: "悬念"),
        Demo(daysAgo: 0, hour: 15, minute: 0, site: "github.com", title: "apple/swift-async-algorithms", author: nil, minutes: 12, junk: false, category: "技术", hook: nil),
        Demo(daysAgo: 0, hour: 20, minute: 0, site: "youtube.com", title: "纪录片：人类的起源 第一集", author: "BBC Earth", minutes: 25, junk: false, category: "知识科普", hook: nil),
        Demo(daysAgo: 0, hour: 23, minute: 5, site: "douyin.com", title: "沙雕合集，笑到停不下来 #搞笑", author: "快乐小王", minutes: 12, junk: true, category: "搞笑", hook: "搞笑"),
        Demo(daysAgo: 0, hour: 23, minute: 18, site: "douyin.com", title: "情侣吵架名场面", author: "情感小屋", minutes: 8, junk: true, category: "情感", hook: "愤怒"),
    ]
    for d in 1...12 {
        demo.append(Demo(daysAgo: d, hour: 22 + d % 2, minute: 10, site: "douyin.com", title: "搞笑短视频 \(d)", author: "某人",
                         minutes: Double(10 + (d * 7) % 35), junk: true, category: d % 3 == 0 ? "情感" : "搞笑", hook: "搞笑"))
        demo.append(Demo(daysAgo: d, hour: 10, minute: 0, site: "bilibili.com", title: "学习视频 \(d)", author: "某老师",
                         minutes: Double(15 + (d * 11) % 40), junk: false, category: "学习", hook: nil))
    }
    for (i, d) in demo.enumerated() {
        let day = cal.date(byAdding: .day, value: -d.daysAgo, to: cal.startOfDay(for: Date()))!
        let start = day.addingTimeInterval(Double(d.hour * 3600 + d.minute * 60)).timeIntervalSince1970
        var v = ContentView(viewId: "demo\(i)", url: "https://www.\(d.site)/\(i)", title: d.title, author: d.author,
                            kind: "video", startedAt: start, endedAt: start + d.minutes * 60, activeSeconds: d.minutes * 60)
        try? store.upsert(v)
        v.label = ContentLabel(isJunk: d.junk, nutrition: d.junk ? 1 : 4, category: d.category,
                               reason: d.junk ? "纯娱乐，看完没有收获" : "能学到东西", model: "deepseek-flash", hook: d.hook)
        try? store.setLabel(viewId: v.viewId, label: v.label!)
        if d.daysAgo == 0 {
            stats.add("site:" + d.site + (d.junk ? "" : UsageStats.nutritiousSuffix), seconds: d.minutes * 60, at: day)
        }
    }
    for r in [ReasonKind.tired, .tired, .bored, .avoiding] {
        try? store.addReason(NudgeReason(at: Date(), reason: r, site: "douyin.com", sessionMinutes: 20))
    }
    try? store.saveDigest(Digest(day: DayKey.string(Date()), text: DailyReport(
        headline: "深夜的抖音是今天唯一的失守",
        findings: ["23 点后连看搞笑和吵架视频 20 分钟，你点的原因是“累了”", "白天 Swift 教程和纪录片都看完了，学习时段很完整", "中午只刷了 5 分钟就停下，提醒起了作用"],
        tomorrow: "23:00 后打开抖音先停 10 秒再决定",
        setting: Suggestion(kind: .pauseBeforeJunk, site: "", minutes: 0)).json, model: "deepseek-v4-pro"))
    try? store.saveDigest(Digest(day: Week(containing: Date()).key, text: WeeklyReport(
        headline: "一周的失守都在 23 点以后", patterns: ["5 个晚上在 23 点后刷抖音，白天几乎不刷", "被吸引的主要是搞笑和情感吵架"],
        cause: "四次提醒里三次你说“累了”", actions: ["23:00 后开启“打开前先停一下”", "睡前用 10 分钟纪录片替代短视频"],
        alternative: "爱看搞笑 → 脱口秀专场", commitment: "下周 23 点后抖音不超过 10 分钟").json,
        model: "deepseek-v4-pro", createdAt: Date().timeIntervalSince1970 - 100))

    _ = try? store.saveFavorite(Favorite(url: "https://www.bilibili.com/video/BV1demo", title: "Swift 并发编程入门：async/await 实战",
                                         author: "程序员小李", text: "", textKind: .none, savedAt: Date().timeIntervalSince1970 - 60))
    let favID = try? store.saveFavorite(Favorite(url: "https://www.ruanyifeng.com/blog/2024/10/weekly-issue-321.html",
                                                 title: "科技爱好者周刊（第 321 期）：傅盛回忆录", author: "阮一峰",
                                                 text: "……", textKind: .article))
    if let favID {
        try? store.setFavoriteResult(id: favID, points: KeyPoints(
            summary: "本期周刊以傅盛回忆录为主线，记录猎豹多次转型求生",
            points: ["金山毒霸 2010 年改免费、靠流量广告，止住收入下滑并活下来", "正面对抗 360 无效：新功能两周被复制，小公司难在大公司主战场取胜",
                     "避开 PC 安全，专攻海外移动清理工具 Clean Master，集中资源做到日活过亿",
                     "上市后多元投资移动广告和 Musical.ly；工具流量随系统权限收紧而衰退"]), error: nil)
    }
    let settings = SettingsModel(config: config) { _ in }
    let model = MainModel(stats: stats, config: config, settings: settings)
    model.contentStore = store
    model.digestWriter = DigestWriter(store: store)
    model.todayJunkSeconds = 25.5 * 60
    for page in Page.allCases {
        MainWindow.renderPNG(model: model, page: page, to: URL(fileURLWithPath: dir).appendingPathComponent("main-\(page).png"))
    }
}

/// 开发用：单独显示桌宠，按顺序切换表情、说话、施法，并截图
@MainActor
func runMascotDemo(to dir: String) {
    NSApplication.shared.setActivationPolicy(.accessory)
    let mascot = Mascot()
    mascot.voiceEnabled = false
    mascot.onError = { print("桌宠出错：", $0) }
    mascot.show()
    let out = URL(fileURLWithPath: dir)
    var steps: [(String, @MainActor () -> Void)] = (1...8).map { i in
        ("exp_0\(i)", { mascot.js("mascot.expr('exp_0\(i)')") })
    }
    steps.append(("bubble", {
        mascot.js("mascot.setMood('angry')")
        mascot.say("看了这么久了还不关！再刷就要被我施魔法了哦。",
                   buttons: [Mascot.BubbleButton(id: "rest", title: "好，关掉它", primary: true),
                             Mascot.BubbleButton(id: "snooze", title: "再刷 5 分钟", waitSeconds: 10)],
                   reasons: ReasonKind.allCases)
    }))
    steps.append(("cast", { mascot.hideBubble(); mascot.js("mascot.setMood('angry'); mascot.cast(-1, -0.7)") }))
    steps.append(("burst", { mascot.js("mascot.burst()") }))

    @MainActor func run(_ i: Int) {
        guard i < steps.count else { exit(0) }
        steps[i].1()
        DispatchQueue.main.asyncAfter(deadline: .now() + (steps[i].0 == "cast" ? 1.0 : steps[i].0 == "burst" ? 0.35 : 1.6)) {
            MainActor.assumeIsolated {
                mascot.snapshot(to: out.appendingPathComponent("mascot-\(steps[i].0).png")) {
                    MainActor.assumeIsolated { run(i + 1) }
                }
            }
        }
    }
    @MainActor func waitReady(_ tries: Int) {
        if mascot.isReady {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { run(0) } }
        } else if tries > 100 {
            print("桌宠 10 秒内没有加载完成")
            exit(1)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { waitReady(tries + 1) } }
        }
    }
    waitReady(0)
}
