import AppKit
import ServiceManagement
import WhaleUpCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = ActivityMonitor()
    private let nudgeWindow = NudgeWindow()
    private let toast = Toast()
    private let pausePanel = PausePanel()
    /// 桌宠（开启且模型文件在时才有）
    private var mascot: Mascot?
    private var mascotBehavior = MascotBehavior()
    private var wasJunk = false
    private var lastPauseAt: Date?
    private var main: MainWindow?
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
            self?.main?.model.version += 1
            if automatic {
                let what = digest.day.contains("W") ? "\(digest.day) 的每周复盘"
                    : "\(digest.day == DayKey.string(Date()) ? "今天" : digest.day) 的小结"
                self?.toast.show("📝 \(what)写好了，点 🌱 →“每日小结”查看")
            }
        }
        return w
    }
    private lazy var favorites: FavoriteExtractor? = contentStore.map { store in
        let f = FavoriteExtractor(store: store)
        f.onChange = { [weak self] done in
            self?.main?.model.version += 1
            if let done {
                self?.toast.show(done.points?.worth == false ? "⭐ \(done.title)：没有值得留下的内容" : "⭐ 要点提取好了：\(done.title)")
            }
        }
        return f
    }
    private lazy var labeler: Labeler? = contentStore.map { store in
        let l = Labeler(store: store)
        l.onChange = { [weak self] in
            self?.main?.model.version += 1
            self?.main?.model.settings.labelerStatus = self?.labelerStatus
        }
        return l
    }
    private var pausedUntil: Date?
    /// 最近一次提醒时在前台的 App，点“去休息”时把它隐藏
    private var nudgedBundleID: String?
    private var nudgedURL: String?

    private let debug = ProcessInfo.processInfo.environment["WHALEUP_DEBUG"] != nil

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
        updateMascot()
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
                self.main?.model.settings.extensionLastSeen = Date()
                self.main?.model.version += 1
                self.labeler?.kick(config: self.config)
            },
            status: { [weak self] in
                guard let self else { return [:] }
                let today = LogicalDay.range(Date())
                let count = (try? self.contentStore?.views(from: today.start, to: today.end))??.count ?? 0
                return ["ok": true, "scope": self.config.contentScope.rawValue, "todayViews": count]
            })
        server?.onFavorite = { [weak self] input in
            guard let self, let favorites = self.favorites else { return "鲸醒还没准备好" }
            let kind = Favorite.TextKind(rawValue: input.textKind ?? "") ?? .none
            let reason = favorites.save(Favorite(url: input.url, title: input.title ?? input.url, author: input.author,
                                                 text: input.text ?? "", textKind: kind), config: self.config)
            if reason == nil { self.toast.show("⭐ 已收藏，正在提取要点") }
            return reason
        }
        server?.start()
        favorites?.kick(config: config)  // 处理上次没提取完的
        labeler?.kick(config: config)  // 处理上次没判断完的
    }

    /// 在“应用程序”或启动台里再次打开时，显示主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(nil)
        return true
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
            main?.model.settings.browserURL = url
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

        // 桌宠的小动作：离开时睡觉、饭点吃饭、坐久了伸懒腰、偶尔打哈欠
        if let mascot, mascot.isShown, config.mascotAutoActions, mascot.playing == nil || mascot.playing == "sleep" {
            for event in mascotBehavior.update(now: now, idleSeconds: monitor.idleSeconds(),
                                               isJunk: currentReason != nil, config: config) {
                switch event {
                case .start(let action, let line):
                    mascot.play(action)
                    if let line { mascot.remark(line, seconds: 5) }
                case .stop:
                    mascot.stopAction()
                }
            }
        }

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
            print("[\(now)] \(current?.appName ?? "-") \(current?.url ?? "") junk=\(currentReason ?? "no") idle=\(idle) session=\(Int(tracker.sessionSeconds))s today=\(Int(tracker.todaySeconds))s force=\(Int(forceUsedToday))s")
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
        main?.model.stats = stats
        main?.model.version += 1
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveStats()
    }

    /// 今天没营养内容的总时长（来自统计，规则改了会重新归类）
    private var todayJunkItems: [UsageItem] { stats.items(on: Date(), config: config).filter(\.isJunk) }
    private var todayJunkSeconds: Double { todayJunkItems.reduce(0) { $0 + $1.seconds } }

    /// 设置页上显示的“今天已看 / 今天能看”
    private func refreshForceToday() {
        guard let settings = main?.model.settings else { return }
        let value = (used: forceUsedToday, limit: forceCloser.limitSeconds(config: config), extra: forceCloser.extraSeconds,
                     grantsLeft: forceCloser.grantsLeft())
        if settings.forceToday != value { settings.forceToday = value }
    }

    /// 今天在强制关闭名单网站上累计看了多久（和统计里看到的一样，后台播放的视频也算）
    private var forceUsedToday: Double { stats.seconds(on: Date(), sites: config.forceCloseSites) }

    /// 强制关闭模式：今天在名单网站上累计看够了，就直接关掉当前网页；当天再打开也会被关掉
    private func enforce(idle: Bool, now: Date, elapsed: Double) {
        let rule = current?.url.flatMap { Classifier.matchSite($0, rules: config.forceCloseSites) }
        // 强制关闭只针对名单里的网站；大模型判断为有营养的内容不管
        let onSite = rule != nil && JunkJudge.isJunk(siteRuleMatched: true, label: currentLabel, config: config)
        let action = forceCloser.record(onSite: onSite, usedToday: forceUsedToday, now: now, config: config)
        refreshForceToday()
        switch action {
        case .warn:
            toast.show("⏳ 还有 1 分钟，\(rule ?? "") 将被自动关闭")
        case .close:
            if let id = current?.bundleID {
                let url = current?.url
                // 暂停只停提醒，强制关闭照关：这时让她说清楚，免得以为暂停坏了
                let line = pausedUntil != nil ? "暂停只停提醒，强制关闭还是要关的哦！" : "看了这么久了还不关！"
                closeWithMagic(line: line, bundleID: id) { [weak self] in
                    guard let self else { return }
                    self.monitor.closeJunk(bundleID: id, nudgedURL: url, rules: self.config.forceCloseSites)
                }
            }
            nudgeWindow.close()
            tracker.acceptRest()
            toast.show("🚫 今天在 \(config.forceCloseSites.joined(separator: "、")) 上已经看了 \(formatDuration(forceUsedToday))，已关掉 \(rule ?? "")\n今天再打开也会被关掉；真要多看，去设置里给今天加时间")
        case nil:
            break
        }

        // 每日额度用完且设置了直接关闭：刷没营养的网页就关掉（10 秒内只关一次）
        if config.budgetCloses, currentReason != nil, let activity = current, activity.url != nil,
           config.budgetRemainingSeconds(usedToday: tracker.todaySeconds) == 0,
           now.timeIntervalSince(lastBudgetCloseAt) > 10, let id = activity.bundleID {
            lastBudgetCloseAt = now
            let site = currentReason ?? "这个网页"
            closeWithMagic(line: "今天的额度用完啦！", bundleID: id) { [weak self] in
                guard let self else { return }
                if self.monitor.closeJunk(bundleID: id, nudgedURL: activity.url, rules: self.config.junkSites + self.config.forceCloseSites) {
                    self.nudgeWindow.close()
                    self.toast.show("⛽️ 今天 \(Int(self.config.dailyBudgetMinutes)) 分钟的额度用完了，已关掉 \(site)")
                }
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
        let friction = Friction.level(for: nudge, config: config)
        if let mascot, mascot.isShown, friction != .writeReason(waitSeconds: config.frictionWaitSeconds) {
            // 桌宠在头顶气泡里提醒，并读出来；要写理由的那一级仍用弹窗（需要打字）
            var wait = 0
            if case .wait(let s) = friction { wait = s }
            mascot.say(text.body, speak: text.body, buttons: [
                Mascot.BubbleButton(id: "rest", title: nudge.isNight ? "好，关掉去睡觉" : "好，关掉它", primary: true),
                Mascot.BubbleButton(id: "snooze", title: "再刷 \(Int(config.snoozeMinutes)) 分钟", waitSeconds: wait),
            ], reasons: ReasonKind.allCases, onButton: { [weak self] id in
                self?.mascot?.hideBubble()
                if id == "rest" { record(.accepted, nil); self?.acceptRest() } else { record(.snoozed, nil) }
            }, onReason: { [weak self] kind in
                try? self?.contentStore?.addReason(
                    NudgeReason(at: Date(), reason: kind, site: nudge.reason, sessionMinutes: nudge.sessionMinutes))
            })
            return
        }
        nudgeWindow.show(text, isNight: nudge.isNight, snoozeMinutes: Int(config.snoozeMinutes),
                         friction: friction,
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
            let url = nudgedURL
            closeWithMagic(line: "好，交给我吧！", bundleID: id) { [weak self] in
                guard let self else { return }
                self.monitor.closeJunk(bundleID: id, nudgedURL: url, rules: self.config.junkSites)
            }
        }
        updateStatusTitle()
    }

    /// 有桌宠时让她飞过去施法关掉；没有就直接关
    private func closeWithMagic(line: String, bundleID: String, close: @escaping () -> Void) {
        guard let mascot, mascot.isShown else { return close() }
        mascot.castAndClose(line: line, browserBundleID: bundleID, close: close)
    }

    /// 桌宠此刻的表情
    private var mascotMood: Mascot.Mood {
        if pausedUntil != nil { return .idle }
        if currentReason != nil {
            let limit = config.limitSeconds(at: Date())
            return tracker.sessionSeconds >= limit * 0.7 ? .angry : .watching
        }
        if let label = currentLabel, !label.isJunk { return .happy }
        return .idle
    }

    /// 按设置显示或收起桌宠
    private func updateMascot() {
        if config.mascotEnabled, Mascot.assetsDir != nil {
            if let m = mascot, m.characterID != config.mascotCharacter {
                m.hide()  // 换角色：重新创建
                mascot = nil
            }
            if mascot == nil {
                let m = Mascot()
                m.characterID = config.mascotCharacter
                m.onTapped = { [weak self] in
                    guard let self, let m = self.mascot else { return }
                    let used = self.tracker.todaySeconds
                    let line: String
                    if used < 60 { line = "今天表现不错哦，继续保持～" }
                    else if let left = self.config.budgetRemainingSeconds(usedToday: used) {
                        line = left > 0 ? "今天已经刷了 \(formatDuration(used))，额度还剩 \(formatDuration(left))。"
                                        : "今天的额度已经用完了，别再刷啦！"
                    } else { line = "今天已经刷了 \(formatDuration(used)) 没营养的内容了哦。" }
                    m.remark(line)
                }
                m.onError = { [weak self] in self?.toast.show("桌宠加载失败：\($0)") }
                m.onMenu = { [weak self] option in option ? self?.showMascotMenu() : self?.showMascotRing() }
                m.onRing = { [weak self] id in self?.handleRing(id) }
                m.show()
                mascot = m
            }
            mascot?.voiceEnabled = config.mascotVoice
            mascot?.voice.voiceID = config.mascotVoiceName
        } else {
            mascot?.hide()
            mascot = nil
        }
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
        let (loaded, error) = Config.load()
        // 直接改配置文件来放松管控：不生效，写回原来的（要放松得在设置里输随机码）
        if configLoaded, error == nil, !loaded.loosenings(from: config).isEmpty, !CodeGate.isUnlocked {
            config.save()
            configModifiedAt = modificationDate(of: Config.fileURL)
            toast.show("🔒 配置文件里放松管控的改动没有生效\n要放松，请在设置里改（需要输随机码）")
            return
        }
        (config, configError) = (loaded, error)
        configLoaded = true
        LogicalDay.startHour = config.dayStartHour
        configModifiedAt = modificationDate(of: Config.fileURL)
        if timer != nil, config.checkIntervalSeconds != oldInterval { scheduleTimer() }
        if timer != nil { updateMascot() }
        main?.model.settings.replace(with: config)
        main?.model.config = config
    }

    private var labelerStatus: String? {
        guard let labeler else { return nil }
        if let error = labeler.lastError { return "⚠️ \(error)" }
        if let at = labeler.lastSuccessAt { return "最近一次判断：\(at.formatted(date: .omitted, time: .shortened))" }
        return nil
    }

    /// 启动时读过一次配置以后，再读到的放松改动都要输随机码
    private var configLoaded = false

    /// 设置页或菜单改了配置：保存并立即生效。放松管控的改动要先输随机码
    private func applyConfig(_ new: Config) {
        let loosened = new.loosenings(from: config)
        if !loosened.isEmpty && !CodeGate.isUnlocked {
            // 先把界面改回去，再弹随机码（不在 SwiftUI 改值的过程里弹窗）
            main?.model.settings.replace(with: config)
            DispatchQueue.main.async { [weak self] in
                guard let self, CodeGate.confirm(loosened) else { return }
                self.applyConfig(new)
                self.toast.show("🔓 已经改了：\(loosened.joined(separator: "；"))")
            }
            return
        }
        let oldInterval = config.checkIntervalSeconds
        config = new
        configError = nil
        LogicalDay.startHour = config.dayStartHour
        config.save()
        configModifiedAt = modificationDate(of: Config.fileURL)
        if config.checkIntervalSeconds != oldInterval { scheduleTimer() }
        main?.model.settings.replace(with: config)
        main?.model.config = config
        labeler?.kick(config: config)
        updateMascot()
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
        mascot?.setMood(mascotMood)
        main?.model.todayJunkSeconds = tracker.todaySeconds
        main?.model.pausedUntil = pausedUntil
        let minutes = Int(todayJunkSeconds / 60)
        let icon: String
        if pausedUntil != nil { icon = "⏸" }
        else if currentReason != nil { icon = "👀" }
        else { icon = "🌱" }
        statusItem.button?.title = minutes > 0 ? "\(icon) \(minutes)′" : icon
        statusItem.button?.toolTip = "鲸醒：今天刷了 \(minutes) 分钟没营养的内容"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fillMenu(menu)
    }

    /// 今天的一句话概况（菜单栏菜单和右键圆环共用）
    private func todayStatus() -> String {
        var status = "今天没营养 \(formatDuration(tracker.todaySeconds))"
        if let left = config.budgetRemainingSeconds(usedToday: tracker.todaySeconds) {
            status += left > 0 ? "，额度还剩 \(formatDuration(left))" : "，额度已用完"
        }
        return status
    }

    /// 动作的小图标
    private static let actionIcons = ["eat": "🍚", "sleep": "😴", "yawn": "🥱", "stretch": "🙆", "swim": "🏊",
                                      "dance": "💃", "work": "💻", "heart": "💗", "milktea": "🧋", "read": "📖"]

    /// 右键点桌宠：功能围着她弹出一圈。第一圈是常用的 6 个，动作、加入名单、更多点开是第二圈
    private func showMascotRing() {
        guard let mascot else { return }
        typealias Item = Mascot.RingItem
        let actions = mascot.actions.map { name in
            Item(id: "act:\(name)", title: Mascot.actionInfo[name]?.title ?? name,
                 icon: Self.actionIcons[name] ?? "✨", on: mascot.playing == name)
        }
        let rule = lastBrowserURL.flatMap(Classifier.siteRule(from:))
        let lists: [Item] = [
            Item(id: "add:junk", title: "没营养", icon: "🍿", on: rule.map(config.junkSites.contains) ?? false),
            Item(id: "add:force", title: "强制关闭", icon: "⛔️", on: rule.map(config.forceCloseSites.contains) ?? false),
            Item(id: "add:sensitive", title: "不记录", icon: "🔒", on: rule.map(config.sensitiveSites.contains) ?? false),
        ].map { var i = $0; i.disabled = rule == nil || i.on; return i }
        var more: [Item] = [
            Item(id: "main", title: "主窗口", icon: "🏠"),
            Item(id: "settings", title: "设置", icon: "⚙️"),
            Item(id: "force", title: "强制关闭", icon: "🛡️", on: config.forceCloseEnabled),
        ]
        if mascot.playing == "sleep" { more.append(Item(id: "wake", title: "叫醒她", icon: "⏰")) }
        more += [Item(id: "hide", title: "隐藏她", icon: "🙈"), Item(id: "quit", title: "退出", icon: "🚪")]
        let items: [Item] = [
            Item(id: "actions", title: "动作", icon: "🎀", children: actions),
            Item(id: "cast", title: "施魔法", icon: "🪄"),
            Item(id: "today", title: "今天", icon: "📊"),
            Item(id: "lists", title: "加入名单", icon: "📌", disabled: rule == nil, children: lists,
                 note: rule.map { "把 \($0) 加入…" }),
            pausedUntil == nil ? Item(id: "pause", title: "暂停提醒", icon: "⏸️") : Item(id: "resume", title: "恢复监测", icon: "▶️"),
            Item(id: "more", title: "更多", icon: "💭", children: more),
        ]
        mascot.openRing(items, status: todayStatus())
    }

    private func handleRing(_ id: String) {
        guard let mascot else { return }
        if id.hasPrefix("act:") {
            let name = String(id.dropFirst(4))
            if mascot.playing == name { mascot.stopAction(); return }
            mascot.play(name)
            if let line = Mascot.actionInfo[name]?.line { mascot.remark(line, seconds: 3) }
            return
        }
        let rule = lastBrowserURL.flatMap(Classifier.siteRule(from:))
        switch id {
        case "cast": mascotCast()
        case "today":
            var line = todayStatus()
            if let reason = currentReason { line += "。现在在看 \(reason)，已经连续 \(formatDuration(tracker.sessionSeconds)) 了" }
            mascot.remark(line + "。", seconds: 6)
        case "add:junk": if let rule { addJunkSite(rule) }
        case "add:force": if let rule { addForceSite(rule) }
        case "add:sensitive": if let rule { addSensitiveSite(rule) }
        case "pause":
            pauseOneHour()
            mascot.remark(config.forceCloseEnabled ? "好，这一个小时我不唠叨你～不过强制关闭还是照关哦。" : "好，这一个小时我不唠叨你～", seconds: 4)
        case "resume": resume(); mascot.remark("我回来盯着你啦！", seconds: 3)
        case "main": openMain()
        case "settings": openSettings()
        case "force": toggleForceClose()
        case "wake": mascotWake()
        case "hide": hideMascot()
        case "quit": quit()
        default: break
        }
    }

    /// 右键点桌宠时按着 Option：系统菜单（先是她的动作，再是和菜单栏一样的功能）
    private func showMascotMenu() {
        guard let mascot else { return }
        let menu = NSMenu()
        let actionsItem = NSMenuItem(title: "动作", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for name in mascot.actions {
            let item = NSMenuItem(title: Mascot.actionInfo[name]?.title ?? name, action: #selector(mascotAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = mascot.playing == name ? .on : .off
            sub.addItem(item)
        }
        let cast = NSMenuItem(title: "施魔法", action: #selector(mascotCast), keyEquivalent: "")
        cast.target = self
        sub.addItem(.separator())
        sub.addItem(cast)
        actionsItem.submenu = sub
        menu.addItem(actionsItem)
        if mascot.playing == "sleep" {
            let wake = NSMenuItem(title: "叫醒她", action: #selector(mascotWake), keyEquivalent: "")
            wake.target = self
            menu.addItem(wake)
        }
        let hide = NSMenuItem(title: "暂时隐藏桌宠", action: #selector(hideMascot), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())
        fillMenu(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func mascotAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let mascot else { return }
        mascot.play(name)
        if let line = Mascot.actionInfo[name]?.line { mascot.remark(line, seconds: 3) }
    }

    @objc private func mascotCast() {
        guard let mascot else { return }
        let browser = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac"].first {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        mascot.castAndClose(line: "看我的魔法！", browserBundleID: browser) {}
    }

    @objc private func mascotWake() {
        mascot?.stopAction()
        mascot?.play("yawn")
    }

    @objc private func hideMascot() {
        var new = config
        new.mascotEnabled = false
        applyConfig(new)
        toast.show("桌宠已隐藏，可以在“设置 → 提醒 → 桌宠”里重新打开")
    }

    private func fillMenu(_ menu: NSMenu) {
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

        // 一句话概况
        info(todayStatus())
        if let until = pausedUntil {
            info("已暂停，\(clock(until.timeIntervalSince1970)) 恢复")
        } else if let reason = currentReason {
            info("正在看 \(reason)，连续 \(formatDuration(tracker.sessionSeconds))")
        }
        if config.forceCloseEnabled {
            let used = forceUsedToday
            info(forceCloser.isBlocked(usedToday: used, config: config)
                 ? "强制关闭：今天的 \(formatDuration(forceCloser.limitSeconds(config: config))) 已用完，再打开会被关掉"
                 : "强制关闭：今天还能看 \(formatDuration(forceCloser.remainingSeconds(usedToday: used, config: config)))")
        }
        if !monitor.deniedBrowsers.isEmpty {
            _ = action("⚠️ 读不到 \(monitor.deniedBrowsers.sorted().joined(separator: "、")) 的网址，去授权…", #selector(openAutomationSettings))
        }
        if let configError { info("⚠️ \(configError)") }

        menu.addItem(.separator())
        _ = action("打开鲸醒", #selector(openMain), key: "o")
        if let url = lastBrowserURL, let rule = Classifier.siteRule(from: url) {
            let add = NSMenuItem(title: "把 \(rule) 加入…", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, inList, selector) in [
                ("没营养网站（超时提醒）", config.junkSites.contains(rule), #selector(addToJunkSites(_:))),
                ("强制关闭网站", config.forceCloseSites.contains(rule), #selector(addToForceSites(_:))),
                ("永不记录的网站", config.sensitiveSites.contains(rule), #selector(addToSensitiveSites(_:))),
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

        menu.addItem(.separator())
        _ = pausedUntil != nil ? action("恢复监测", #selector(resume)) : action("暂停提醒 1 小时", #selector(pauseOneHour))
        let force = action("强制关闭模式", #selector(toggleForceClose))
        force.state = config.forceCloseEnabled ? .on : .off

        menu.addItem(.separator())
        _ = action("设置…", #selector(openSettings), key: ",")
        _ = action("退出", #selector(quit), key: "q")
    }

    @objc private func addToSensitiveSites(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        addSensitiveSite(rule)
    }

    private func addSensitiveSite(_ rule: String) {
        var new = config
        new.sensitiveSites.append(rule)
        applyConfig(new)
        toast.show("🔒 以后不再记录 \(rule)")
    }

    @objc private func toggleForceClose() {
        var new = config
        new.forceCloseEnabled.toggle()
        applyConfig(new)
        // 关掉要输随机码，结果由 applyConfig 提示
        if new.forceCloseEnabled {
            toast.show("🔒 强制关闭已开启：\(config.forceCloseSites.joined(separator: "、")) 每天累计看 \(Int(config.forceCloseMinutes)) 分钟会被自动关掉")
        }
    }

    @objc private func pauseOneHour() {
        pausedUntil = Date().addingTimeInterval(3600)
        tick()
    }

    @objc private func resume() {
        pausedUntil = nil
        tick()
    }


    private func deleteDay(_ day: Date) {
        let (start, end) = LogicalDay.range(day)
        try? contentStore?.deleteDay(from: start, to: end, dayKey: DayKey.string(day))
        stats.removeDay(start)
        saveStats()
        main?.model.version += 1
    }

    private func deleteSite(_ site: String) {
        try? contentStore?.deleteSite(site)
        stats.removeSite(site)
        saveStats()
        main?.model.version += 1
    }

    @objc private func openMain() {
        showMain(nil)
    }

    @objc private func openSettings() {
        showMain(.settings)
    }

    private func showMain(_ page: Page?) {
        saveStats()
        if main == nil {
            let settings = SettingsModel(config: config) { [weak self] in self?.applyConfig($0) }
            settings.browserURL = lastBrowserURL
            settings.extensionLastSeen = server?.lastReportAt
            settings.serverError = server?.error ?? (contentStore == nil ? "内容数据库打开失败" : nil)
            settings.labelerStatus = labelerStatus
            settings.adjustForce = { [weak self] minutes in
                guard let self else { return }
                if minutes > 0 {
                    // 多看：每天最多 2 次，还要输随机码
                    guard self.forceCloser.grantsLeft() > 0 else {
                        self.toast.show("今天已经多看过 \(ForceCloser.maxGrants) 次了，不能再加了。明天见～")
                        return
                    }
                    let left = self.forceCloser.grantsLeft()
                    DispatchQueue.main.async {
                        guard CodeGate.confirm(["今天多看 \(Int(minutes)) 分钟（今天还能多看 \(left) 次）"]) else { return }
                        self.forceCloser.adjust(minutes: minutes, config: self.config)
                        self.saveTracker()
                        self.refreshForceToday()
                    }
                    return
                }
                self.forceCloser.adjust(minutes: minutes, config: self.config)
                self.saveTracker()
                self.refreshForceToday()
            }
            settings.resetForce = { [weak self] in
                guard let self else { return }
                // 少看了再恢复，等于放松：也要输随机码
                if self.forceCloser.extraSeconds < 0 {
                    DispatchQueue.main.async {
                        guard CodeGate.confirm(["恢复成每天的 \(Int(self.config.forceCloseMinutes)) 分钟"]) else { return }
                        self.forceCloser.resetToday()
                        self.saveTracker()
                        self.refreshForceToday()
                    }
                    return
                }
                self.forceCloser.resetToday()
                self.saveTracker()
                self.refreshForceToday()
            }
            settings.previewVoice = { [weak self] in
                guard let self, let mascot = self.mascot else { return }
                mascot.voice.voiceID = self.config.mascotVoiceName
                mascot.remark("主人好呀～我是你的专注小助手，今天也要好好加油哦！", seconds: 5)
            }
            settings.previewMascot = { [weak self] in
                guard let mascot = self?.mascot else { return }
                let browser = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac"].first {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
                }
                mascot.castAndClose(line: "看了这么久了还不关！", browserBundleID: browser) {}
            }
            let model = MainModel(stats: stats, config: config, settings: settings)
            model.contentStore = contentStore
            model.digestWriter = digestWriter
            model.favorites = favorites
            model.deleteDay = { [weak self] day in self?.deleteDay(day) }
            model.deleteSite = { [weak self] site in self?.deleteSite(site) }
            model.togglePause = { [weak self] in
                guard let self else { return }
                if self.pausedUntil == nil { self.pauseOneHour() } else { self.resume() }
            }
            main = MainWindow(model: model)
        }
        refreshForceToday()
        main?.model.stats = stats
        main?.model.todayJunkSeconds = tracker.todaySeconds
        main?.model.pausedUntil = pausedUntil
        main?.show(page)
    }

    @objc private func addToJunkSites(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        addJunkSite(rule)
    }

    private func addJunkSite(_ rule: String) {
        var new = config
        new.junkSites.append(rule)
        applyConfig(new)
        toast.show("✅ 已把 \(rule) 加入没营养网站")
    }

    @objc private func addToForceSites(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        addForceSite(rule)
    }

    private func addForceSite(_ rule: String) {
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
            alert.informativeText = "请先把 WhaleUp.app 放到“应用程序”文件夹再试。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
