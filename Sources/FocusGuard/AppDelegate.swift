import AppKit
import ServiceManagement
import FocusGuardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = ActivityMonitor()
    private let nudgeWindow = NudgeWindow()
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private var config = Config()
    private var configError: String?
    private var configModifiedAt: Date?

    private var tracker = Tracker()
    private var lastTick = Date()
    private var current: Activity?
    private var currentReason: String?
    private var pausedUntil: Date?
    /// 最近一次提醒时在前台的 App，点“去休息”时把它隐藏
    private var nudgedBundleID: String?

    private let debug = ProcessInfo.processInfo.environment["FOCUSGUARD_DEBUG"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()
        if let data = UserDefaults.standard.data(forKey: "tracker"),
           let saved = try? JSONDecoder().decode(Tracker.self, from: data) {
            tracker = saved
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        scheduleTimer()
        tick()
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

        if let until = pausedUntil, now < until {
            current = nil
            currentReason = nil
        } else {
            pausedUntil = nil
            current = monitor.currentActivity()
            currentReason = current.flatMap { Classifier.junkReason(for: $0, config: config) }
            let idle = monitor.idleSeconds() > config.idleSeconds

            let nudge = tracker.record(isJunk: currentReason != nil, isIdle: idle, now: now, elapsed: elapsed,
                                       config: config, reason: currentReason ?? "",
                                       appName: current?.appName ?? "")
            saveTracker()
            if debug {
                print("[\(now)] \(current?.appName ?? "-") \(current?.url ?? "") junk=\(currentReason ?? "no") idle=\(idle) session=\(Int(tracker.sessionSeconds))s today=\(Int(tracker.todaySeconds))s")
                fflush(stdout)
            }
            if let nudge, !nudgeWindow.isVisible {
                nudgedBundleID = current?.bundleID
                showNudge(nudge)
            }
        }
        updateStatusTitle()
    }

    private func showNudge(_ nudge: Nudge) {
        nudgeWindow.show(Messages.make(for: nudge), isNight: nudge.isNight, snoozeMinutes: Int(config.snoozeMinutes),
                         onRest: { [weak self] in self?.acceptRest() },
                         onSnooze: {},
                         onSleep: { [weak self] in
                             self?.acceptRest()
                             let p = Process()
                             p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                             p.arguments = ["displaysleepnow"]
                             try? p.run()
                         })
    }

    private func acceptRest() {
        tracker.acceptRest()
        saveTracker()
        if let id = nudgedBundleID {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.hide() }
        }
        updateStatusTitle()
    }

    private func saveTracker() {
        if let data = try? JSONEncoder().encode(tracker) {
            UserDefaults.standard.set(data, forKey: "tracker")
        }
    }

    // MARK: - 配置

    private func loadConfig() {
        let oldInterval = config.checkIntervalSeconds
        (config, configError) = Config.load()
        configModifiedAt = modificationDate(of: Config.fileURL)
        if timer != nil, config.checkIntervalSeconds != oldInterval { scheduleTimer() }
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
        let minutes = Int(tracker.todaySeconds / 60)
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

        info("今天刷了 \(Int(tracker.todaySeconds / 60)) 分钟没营养的内容")
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
        if pausedUntil != nil {
            _ = action("恢复监测", #selector(resume))
        } else {
            _ = action("暂停 1 小时", #selector(pauseOneHour))
        }
        _ = action("预览提醒效果", #selector(previewNudge))

        menu.addItem(.separator())
        _ = action("编辑规则…", #selector(editConfig), key: ",")
        let login = action("开机自动启动", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        _ = action("退出", #selector(quit), key: "q")
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

    @objc private func editConfig() {
        if !FileManager.default.fileExists(atPath: Config.fileURL.path) { config.save() }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([Config.fileURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
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
