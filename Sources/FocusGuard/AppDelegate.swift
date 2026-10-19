import AppKit
import ServiceManagement
import FocusGuardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = ActivityMonitor()
    private let nudgeWindow = NudgeWindow()
    private let toast = Toast()
    private let pausePanel = PausePanel()
    private var wasJunk = false
    private var lastPauseAt: Date?
    private var settings: SettingsWindow?
    private var statsWindow: StatsWindow?
    private var stats = UsageStats.load()
    private var lastStatsSave = Date()
    /// 看过的内容和劝导原因（本地 SQLite）
    private let contentStore = try? ContentStore()
    private var server: LocalServer?
    /// 最近一次在浏览器里看到的网页，用于“把当前网页加入列表”
    private var lastBrowserURL: String?
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private var config = Config()
    private var configError: String?
    private var configModifiedAt: Date?

    private var tracker = Tracker()
    private var forceCloser = ForceCloser()
    private var lastTick = Date()
    private var current: Activity?
    private var currentReason: String?
    /// 大模型对当前网页的判断（开启 AI 判断且已判断过时才有）
    private var currentLabel: ContentLabel?
    private lazy var digestWriter: DigestWriter? = contentStore.map { store in
        let w = DigestWriter(store: store)
        w.onWritten = { [weak self] digest, automatic in
            self?.statsWindow?.model.contentVersion += 1
            if automatic {
                let what = digest.day.contains("W") ? "\(digest.day) 的每周复盘"
                    : "\(digest.day == DayKey.string(Date()) ? "今天" : digest.day) 的小结"
                self?.toast.show("📝 \(what)写好了，点 🌱 →“每日小结”查看")
            }
        }
        return w
    }
    private lazy var labeler: Labeler? = contentStore.map { store in
        let l = Labeler(store: store)
        l.onChange = { [weak self] in
            self?.statsWindow?.model.contentVersion += 1
            self?.settings?.model.labelerStatus = self?.labelerStatus
        }
        return l
    }
    private var pausedUntil: Date?
    /// 最近一次提醒时在前台的 App，点“去休息”时把它隐藏
    private var nudgedBundleID: String?
    private var nudgedURL: String?

    private let debug = ProcessInfo.processInfo.environment["FOCUSGUARD_DEBUG"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()
        if let data = UserDefaults.standard.data(forKey: "tracker"),
           let saved = try? JSONDecoder().decode(Tracker.self, from: data) {
            tracker = saved
        }
        if let data = UserDefaults.standard.data(forKey: "forceCloser"),
           let saved = try? JSONDecoder().decode(ForceCloser.self, from: data) {
            forceCloser = saved
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        ExtensionFiles.install()
        enableLaunchAtLoginOnFirstInstall()
        startServer()
        try? contentStore?.prune(before: Date().addingTimeInterval(-90 * 86400))

        scheduleTimer()
        tick()
    }

    /// 第一次从“应用程序”文件夹启动时自动设为开机启动；之后以用户在菜单里的选择为准
    private func enableLaunchAtLoginOnFirstInstall() {
        let key = "didAutoEnableLaunchAtLogin"
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    /// 接收浏览器扩展上报的观看记录，按“内容记录范围”过滤后存库
    private func startServer() {
        server = LocalServer(
            onViews: { [weak self] views in
                guard let self, let store = self.contentStore else { return }
                for v in views where self.config.shouldRecordContent(url: v.url) {
                    try? store.upsert(v)
                }
                self.settings?.model.extensionLastSeen = Date()
                self.statsWindow?.model.contentVersion += 1
                self.labeler?.kick(config: self.config)
            },
            status: { [weak self] in
                guard let self else { return [:] }
                let today = Calendar.current.startOfDay(for: Date())
                let count = (try? self.contentStore?.views(from: today, to: today.addingTimeInterval(86400)))??.count ?? 0
                return ["ok": true, "scope": self.config.contentScope.rawValue, "todayViews": count]
            })
        server?.start()
        labeler?.kick(config: config)  // 处理上次没判断完的
    }

    // MARK: - 检测循环

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(1, config.checkIntervalSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        reloadConfigIfChanged()
        let now = Date()
        // 电脑睡眠后醒来，间隔会很长，不能把这段时间算进去
        let elapsed = min(now.timeIntervalSince(lastTick), config.checkIntervalSeconds * 2)
        lastTick = now

        if let until = pausedUntil, now >= until { pausedUntil = nil }
        current = monitor.currentActivity()
        // 网站规则先判断；开启 AI 判断后，大模型对这个网页的判断优先
        let ruleReason = current.flatMap { Classifier.junkReason(for: $0, config: config) }
        currentLabel = config.llm.enabled
            ? current?.url.flatMap { try? contentStore?.label(forURL: $0.components(separatedBy: "#")[0]) } ?? nil
            : nil
        currentReason = JunkJudge.isJunk(siteRuleMatched: ruleReason != nil, label: currentLabel, config: config)
            ? (ruleReason ?? currentLabel.map { "\($0.category)内容" })
            : nil
        if let url = current?.url, Classifier.siteRule(from: url) != nil, url != lastBrowserURL {
            lastBrowserURL = url
            settings?.model.browserURL = url
        }
        let idle = monitor.idleSeconds() > config.idleSeconds
        recordUsage(idle: idle, now: now, elapsed: elapsed)

        // 打开前先停一下：从正常内容切到没营养的内容时
        let isJunk = currentReason != nil
        if pausedUntil == nil, !nudgeWindow.isVisible, !nudgePending,
           PauseGate.shouldPause(wasJunk: wasJunk, isJunk: isJunk, lastPauseAt: lastPauseAt, now: now, config: config),
           let activity = current, let id = activity.bundleID {
            lastPauseAt = now
            var detail = "今天已经刷了 \(formatDuration(todayJunkSeconds))"
            if let left = config.budgetRemainingSeconds(usedToday: tracker.todaySeconds) {
                detail += "，额度还剩 \(formatDuration(left))"
            }
            pausePanel.show(site: currentReason ?? activity.appName, detail: detail, seconds: config.frictionWaitSeconds) { [weak self] in
                guard let self else { return }
                self.monitor.closeJunk(bundleID: id, nudgedURL: activity.url, rules: self.config.junkSites + self.config.forceCloseSites)
            }
        }
        wasJunk = isJunk

        // 强制关闭不受“暂停”影响，否则一暂停就绕过去了
        enforce(idle: idle, now: now, elapsed: elapsed)
        digestWriter?.autoRun(config: config, now: now)

        if pausedUntil == nil {
            let nudge = tracker.record(isJunk: currentReason != nil, isIdle: idle, now: now, elapsed: elapsed,
                                       config: config, reason: currentReason ?? "",
                                       appName: current?.appName ?? "")
            if let nudge, !nudgeWindow.isVisible, !nudgePending {
                nudgedBundleID = current?.bundleID
                nudgedURL = current?.url
                showNudge(nudge)
            }
        }
        saveTracker()
        if debug {
            print("[\(now)] \(current?.appName ?? "-") \(current?.url ?? "") junk=\(currentReason ?? "no") idle=\(idle) session=\(Int(tracker.sessionSeconds))s today=\(Int(tracker.todaySeconds))s force=\(Int(forceCloser.sessionSeconds))s")
            fflush(stdout)
        }
        updateStatusTitle()
    }

    /// 统计每个网站 / App 的使用时长（人不在时不算）
    private func recordUsage(idle: Bool, now: Date, elapsed: Double) {
        if !idle, let activity = current,
           activity.bundleID != Bundle.main.bundleIdentifier, activity.bundleID != "com.apple.loginwindow" {
            stats.add(UsageStats.key(for: activity, config: config, label: currentLabel), seconds: elapsed, at: now)
        }
        if now.timeIntervalSince(lastStatsSave) >= 60 { saveStats() }
    }

    private func saveStats() {
        stats.prune(keepingDays: 30, now: Date())
        stats.save()
        lastStatsSave = Date()
        statsWindow?.model.stats = stats
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveStats()
    }

    /// 今天没营养内容的总时长（来自统计，规则改了会重新归类）
    private var todayJunkItems: [UsageItem] { stats.items(on: Date(), config: config).filter(\.isJunk) }
    private var todayJunkSeconds: Double { todayJunkItems.reduce(0) { $0 + $1.seconds } }

    /// 强制关闭模式：在指定网站上停留太久就直接关掉当前网页
    private func enforce(idle: Bool, now: Date, elapsed: Double) {
        let rule = current?.url.flatMap { Classifier.matchSite($0, rules: config.forceCloseSites) }
        // 强制关闭只针对名单里的网站；大模型判断为有营养的内容不计时
        let onSite = rule != nil && JunkJudge.isJunk(siteRuleMatched: true, label: currentLabel, config: config)
        switch forceCloser.record(onSite: onSite, isIdle: idle, now: now, elapsed: elapsed, config: config) {
        case .warn:
            toast.show("⏳ 还有 1 分钟，\(rule ?? "") 将被自动关闭")
        case .close:
            if let id = current?.bundleID {
                monitor.closeJunk(bundleID: id, nudgedURL: current?.url, rules: config.forceCloseSites)
            }
            nudgeWindow.close()
            tracker.acceptRest()
            let until = forceCloser.blockedUntil?.formatted(date: .omitted, time: .shortened) ?? ""
            toast.show("🚫 已自动关闭 \(rule ?? "")\n\(until) 之前再打开会被直接关掉")
        case nil:
            break
        }

        // 每日额度用完且设置了直接关闭：刷没营养的网页就关掉（10 秒内只关一次）
        if config.budgetCloses, currentReason != nil, let activity = current, activity.url != nil,
           config.budgetRemainingSeconds(usedToday: tracker.todaySeconds) == 0,
           now.timeIntervalSince(lastBudgetCloseAt) > 10, let id = activity.bundleID {
            lastBudgetCloseAt = now
            if monitor.closeJunk(bundleID: id, nudgedURL: activity.url, rules: config.junkSites + config.forceCloseSites) {
                nudgeWindow.close()
                toast.show("⛽️ 今天 \(Int(config.dailyBudgetMinutes)) 分钟的额度用完了，已关掉 \(currentReason ?? "这个网页")")
            }
        }
    }

    private var lastBudgetCloseAt = Date.distantPast

    /// 正在请大模型写劝导文案，期间不再触发新的弹窗
    private var nudgePending = false

    /// 弹出劝导：开启 AI 时先请大模型写文案（最多等 4 秒），否则或失败时用固定文案
    private func showNudge(_ nudge: Nudge) {
        guard config.llm.enabled, config.llm.smartNudges, let store = contentStore else {
            return presentNudge(nudge, text: Messages.make(for: nudge), byAI: false)
        }
        nudgePending = true
        let llm = config.llm
        let now = Date()
        let recent = (try? store.views(from: now.addingTimeInterval(-45 * 60), to: now)) ?? []
        let reasons = ((try? store.reasons(from: now.addingTimeInterval(-7 * 86400), to: now)) ?? []).map(\.reason)
        let prompt = NudgePrompt.make(nudge: nudge, recentViews: recent, reasons: reasons,
                                      outcomes: nudgeOutcomeSummary, hourMinute: now.formatted(date: .omitted, time: .shortened))
        Task {
            var text = Messages.make(for: nudge)
            var byAI = false
            do {
                let request = try LLMRequest.chat(NudgePrompt.spec(prompt, llm: llm), llm: llm,
                                                  apiKey: APIKeyStore.get(llm.provider), timeout: 4)
                let (data, _) = try await URLSession.shared.data(for: request)
                text = try NudgePrompt.parse(data, provider: llm.provider)
                byAI = true
            } catch {
                // 超时、断网、格式不对：用固定文案
            }
            nudgePending = false
            presentNudge(nudge, text: text, byAI: byAI)
        }
    }

    /// 最近两周劝导的效果，写进劝导提示词，让大模型知道哪种说法对你有效
    private var nudgeOutcomeSummary: String? {
        let now = Date()
        return NudgeRecord.summary((try? contentStore?.nudges(from: now.addingTimeInterval(-14 * 86400), to: now)) ?? [])
    }

    private func presentNudge(_ nudge: Nudge, text: NudgeText, byAI: Bool) {
        let id = try? contentStore?.addNudge(NudgeRecord(at: Date(), site: nudge.reason, sessionMinutes: nudge.sessionMinutes,
                                                         isNight: nudge.isNight, byAI: byAI, title: text.title, body: text.body))
        let record: (NudgeRecord.Outcome, String?) -> Void = { [weak self] outcome, note in
            if let id { try? self?.contentStore?.setNudgeOutcome(id: id, outcome: outcome, note: note) }
        }
        nudgeWindow.show(text, isNight: nudge.isNight, snoozeMinutes: Int(config.snoozeMinutes),
                         friction: Friction.level(for: nudge, config: config),
                         onRest: { [weak self] in record(.accepted, nil); self?.acceptRest() },
                         onSnooze: { note in record(.snoozed, note) },
                         onReason: { [weak self] kind in
                             try? self?.contentStore?.addReason(
                                 NudgeReason(at: Date(), reason: kind, site: nudge.reason, sessionMinutes: nudge.sessionMinutes))
                         })
    }

    /// 用户同意不刷了：关掉刚才在刷的网页（或退出那个 App），连续时长清零
    private func acceptRest() {
        tracker.acceptRest()
        saveTracker()
        if let id = nudgedBundleID {
            monitor.closeJunk(bundleID: id, nudgedURL: nudgedURL, rules: config.junkSites)
        }
        updateStatusTitle()
    }

    private func saveTracker() {
        if let data = try? JSONEncoder().encode(tracker) {
            UserDefaults.standard.set(data, forKey: "tracker")
        }
        if let data = try? JSONEncoder().encode(forceCloser) {
            UserDefaults.standard.set(data, forKey: "forceCloser")
        }
    }

    // MARK: - 配置

    private func loadConfig() {
        let oldInterval = config.checkIntervalSeconds
        (config, configError) = Config.load()
        configModifiedAt = modificationDate(of: Config.fileURL)
        if timer != nil, config.checkIntervalSeconds != oldInterval { scheduleTimer() }
        settings?.model.replace(with: config)
        statsWindow?.model.config = config
    }

    private var labelerStatus: String? {
        guard let labeler else { return nil }
        if let error = labeler.lastError { return "⚠️ \(error)" }
        if let at = labeler.lastSuccessAt { return "最近一次判断：\(at.formatted(date: .omitted, time: .shortened))" }
        return nil
    }

    /// 设置页或菜单改了配置：保存并立即生效
    private func applyConfig(_ new: Config) {
        let oldInterval = config.checkIntervalSeconds
        config = new
        configError = nil
        config.save()
        configModifiedAt = modificationDate(of: Config.fileURL)
        if config.checkIntervalSeconds != oldInterval { scheduleTimer() }
        settings?.model.replace(with: config)
        statsWindow?.model.config = config
        labeler?.kick(config: config)
    }

    /// 用户保存配置文件后自动生效，无需重启
    private func reloadConfigIfChanged() {
        if modificationDate(of: Config.fileURL) != configModifiedAt { loadConfig() }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - 菜单栏

    private func updateStatusTitle() {
        let minutes = Int(todayJunkSeconds / 60)
        let icon: String
        if pausedUntil != nil { icon = "⏸" }
        else if currentReason != nil { icon = "👀" }
        else { icon = "🌱" }
        statusItem.button?.title = minutes > 0 ? "\(icon) \(minutes)′" : icon
        statusItem.button?.toolTip = "专注守护：今天刷了 \(minutes) 分钟没营养的内容"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }

        info("今天刷了 \(formatDuration(todayJunkSeconds))没营养的内容")
        if let remaining = config.budgetRemainingSeconds(usedToday: tracker.todaySeconds) {
            info(remaining > 0 ? "    今日额度还剩 \(formatDuration(remaining))（共 \(Int(config.dailyBudgetMinutes)) 分钟）"
                               : "    ⛽️ 今日 \(Int(config.dailyBudgetMinutes)) 分钟额度已用完")
        }
        if config.isWorkTime(Date()) { info("    💼 工作时段：连续 \(Int(config.workLimitMinutes)) 分钟就提醒") }
        for item in todayJunkItems.prefix(3) {
            info("    \(item.name)  \(formatDuration(item.seconds))")
        }
        _ = action("查看统计…", #selector(openStats))
        if config.llm.enabled { _ = action("每日小结…", #selector(openDigest)) }
        if let until = pausedUntil {
            info("已暂停，\(until.formatted(date: .omitted, time: .shortened)) 恢复")
        } else if let reason = currentReason {
            info("正在看：\(reason)（本次连续 \(Int(tracker.sessionSeconds / 60)) 分钟）")
        } else {
            info("状态良好 👍")
        }
        let nightNote = config.isNight(Date()) ? "（夜间模式）" : ""
        info("连续 \(Int(config.limitSeconds(at: Date()) / 60)) 分钟提醒\(nightNote)")
        if !monitor.deniedBrowsers.isEmpty {
            info("⚠️ 无法读取 \(monitor.deniedBrowsers.sorted().joined(separator: "、")) 的网址")
            _ = action("去系统设置授权…", #selector(openAutomationSettings))
        }
        if let configError { info("⚠️ \(configError)") }

        menu.addItem(.separator())
        let force = action("强制关闭模式（连续 \(Int(config.forceCloseMinutes)) 分钟自动关网页）", #selector(toggleForceClose))
        force.state = config.forceCloseEnabled ? .on : .off
        if config.forceCloseEnabled {
            if let until = forceCloser.blockedUntil, until > Date() {
                info("    冷却中：\(until.formatted(date: .omitted, time: .shortened)) 前打开会被直接关掉")
            } else if current?.url.flatMap({ Classifier.matchSite($0, rules: config.forceCloseSites) }) != nil {
                info("    当前网页还能看 \(Int(forceCloser.remainingSeconds(config: config) / 60)) 分钟")
            }
        }

        menu.addItem(.separator())
        if pausedUntil != nil {
            _ = action("恢复监测", #selector(resume))
        } else {
            _ = action("暂停 1 小时", #selector(pauseOneHour))
        }
        _ = action("预览提醒效果", #selector(previewNudge))

        menu.addItem(.separator())
        if let url = lastBrowserURL, let rule = Classifier.siteRule(from: url) {
            let add = NSMenuItem(title: "把 \(rule) 加入…", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, inList, selector) in [
                ("没营养网站（超时提醒）", config.junkSites.contains(rule), #selector(addToJunkSites(_:))),
                ("强制关闭网站", config.forceCloseSites.contains(rule), #selector(addToForceSites(_:))),
            ] {
                let item = NSMenuItem(title: title, action: inList ? nil : selector, keyEquivalent: "")
                item.target = self
                item.representedObject = rule
                item.state = inList ? .on : .off
                sub.addItem(item)
            }
            add.submenu = sub
            menu.addItem(add)
        }
        _ = action("设置…", #selector(openSettings), key: ",")
        let login = action("开机自动启动", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        _ = action("退出", #selector(quit), key: "q")
    }

    @objc private func toggleForceClose() {
        var new = config
        new.forceCloseEnabled.toggle()
        applyConfig(new)
        toast.show(config.forceCloseEnabled
                   ? "🔒 强制关闭已开启：\(config.forceCloseSites.joined(separator: "、")) 连续看 \(Int(config.forceCloseMinutes)) 分钟会被自动关掉"
                   : "🔓 强制关闭已关闭")
    }

    @objc private func pauseOneHour() {
        pausedUntil = Date().addingTimeInterval(3600)
        tick()
    }

    @objc private func resume() {
        pausedUntil = nil
        tick()
    }

    @objc private func previewNudge() {
        let night = config.isNight(Date())
        nudgedBundleID = nil
        showNudge(Nudge(reason: "douyin.com", appName: "预览", sessionMinutes: Int(config.limitSeconds(at: Date()) / 60),
                        todayMinutes: Int(tracker.todaySeconds / 60) + 30, isNight: night, count: 1))
    }

    @objc private func openDigest() {
        openStats()
        statsWindow?.model.mode = .digest
    }

    @objc private func openStats() {
        saveStats()
        if statsWindow == nil {
            let model = StatsModel(stats: stats, config: config)
            model.contentStore = contentStore
            model.digestWriter = digestWriter
            statsWindow = StatsWindow(model: model)
        }
        statsWindow?.model.stats = stats
        statsWindow?.show()
    }

    @objc private func openSettings() {
        if settings == nil {
            let model = SettingsModel(config: config) { [weak self] in self?.applyConfig($0) }
            model.browserURL = lastBrowserURL
            model.extensionLastSeen = server?.lastReportAt
            model.serverError = server?.error ?? (contentStore == nil ? "内容数据库打开失败" : nil)
            model.labelerStatus = labelerStatus
            settings = SettingsWindow(model: model)
        }
        settings?.show()
    }

    @objc private func addToJunkSites(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        var new = config
        new.junkSites.append(rule)
        applyConfig(new)
        toast.show("✅ 已把 \(rule) 加入没营养网站")
    }

    @objc private func addToForceSites(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        var new = config
        new.forceCloseSites.append(rule)
        applyConfig(new)
        toast.show(config.forceCloseEnabled ? "✅ 已把 \(rule) 加入强制关闭网站"
                                            : "✅ 已把 \(rule) 加入强制关闭网站（强制关闭模式还没开）")
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法设置开机启动"
            alert.informativeText = "请先把 FocusGuard.app 放到“应用程序”文件夹再试。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
