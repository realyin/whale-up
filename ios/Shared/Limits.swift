import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

/// 主 App 和各个扩展共用的东西：设置存在 App Group 里，扩展读同一份
enum Shared {
    static let group = "group.io.github.realyin.whaleup"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
}

/// 用户的限额设置（主 App 写，扩展读）
struct LimitSettings: Codable, Equatable {
    /// 要管的 App、App 类别和网站
    var selection = FamilyActivitySelection()
    /// 每天在这些 App 上一共能用几分钟
    var dailyMinutes = 30
    /// 一天从几点开始算：这之前的算前一天，和 Mac 版一致
    var dayStartHour = 4
    /// 今天手动加的时间
    var extraMinutes = 0
    var extraDay = ""

    var isEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    private static let key = "limitSettings"

    static func load() -> LimitSettings {
        guard let data = Shared.defaults.data(forKey: key),
              let s = try? PropertyListDecoder().decode(LimitSettings.self, from: data) else { return LimitSettings() }
        return s
    }

    func save() {
        if let data = try? PropertyListEncoder().encode(self) { Shared.defaults.set(data, forKey: Self.key) }
    }

    /// 某个时刻算哪一天（凌晨 dayStartHour 点以前算前一天），如 "2026-10-24"
    func dayKey(_ date: Date = Date()) -> String {
        let shifted = date.addingTimeInterval(-Double(dayStartHour) * 3600)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 今天加的时间（不是今天加的不算）
    var todayExtra: Int { extraDay == dayKey() ? extraMinutes : 0 }
}

extension DeviceActivityName {
    /// 每天从 dayStartHour 点开始的一整天
    static let daily = Self("daily")
    /// 用完以后手动加的时间：从加的那一刻开始单独计
    static let extra = Self("extra")
}

extension DeviceActivityEvent.Name {
    static let warn = Self("warn")
    static let limit = Self("limit")
    static let extraDone = Self("extraDone")
}

extension ManagedSettingsStore.Name {
    static let whale = Self("whale")
}

/// 开始 / 停止计时，锁上 / 解开 App
enum Limiter {
    /// 按设置重新开始每天的计时：从 dayStartHour 点到第二天同一时刻，累计用满就触发 limit，提前 5 分钟触发 warn
    static func restart(_ s: LimitSettings) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.daily])
        guard !s.isEmpty else { unshield(); return }
        let end = (s.dayStartHour + 23) % 24
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: s.dayStartHour, minute: 0),
                                              intervalEnd: DateComponents(hour: end, minute: 59), repeats: true)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [.limit: event(s, minutes: s.dailyMinutes)]
        if s.dailyMinutes > 5 { events[.warn] = event(s, minutes: s.dailyMinutes - 5) }
        try center.startMonitoring(.daily, during: schedule, events: events)
    }

    /// 今天再多给几分钟：先解锁，从现在起单独计时，用完再锁上（到这一天结束为止）
    static func grant(_ minutes: Int) throws {
        var s = LimitSettings.load()
        if s.extraDay != s.dayKey() { s.extraMinutes = 0; s.extraDay = s.dayKey() }
        s.extraMinutes += minutes
        s.save()
        unshield()
        let center = DeviceActivityCenter()
        center.stopMonitoring([.extra])
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        // 计时到这一天结束（凌晨 dayStartHour 点前一分钟）；系统要求一段至少 15 分钟，太晚了就顺延到 15 分钟
        var endHour = (s.dayStartHour + 23) % 24
        var endMinute = 59
        let minutesLeft = ((endHour * 60 + endMinute) - (now.hour! * 60 + now.minute!) + 24 * 60) % (24 * 60)
        if minutesLeft < 15 {
            let t = (now.hour! * 60 + now.minute! + 15) % (24 * 60)
            endHour = t / 60
            endMinute = t % 60
        }
        let schedule = DeviceActivitySchedule(intervalStart: now, intervalEnd: DateComponents(hour: endHour, minute: endMinute), repeats: false)
        try center.startMonitoring(.extra, during: schedule, events: [.extraDone: event(s, minutes: minutes)])
    }

    private static func event(_ s: LimitSettings, minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(applications: s.selection.applicationTokens, categories: s.selection.categoryTokens,
                            webDomains: s.selection.webDomainTokens,
                            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60))
    }

    /// 锁上：打开这些 App 会看到大肥鱼的锁屏页
    static func shield(_ s: LimitSettings = .load()) {
        let store = ManagedSettingsStore(named: .whale)
        store.shield.applications = s.selection.applicationTokens.isEmpty ? nil : s.selection.applicationTokens
        store.shield.applicationCategories = s.selection.categoryTokens.isEmpty ? nil : .specific(s.selection.categoryTokens)
        store.shield.webDomains = s.selection.webDomainTokens.isEmpty ? nil : s.selection.webDomainTokens
        Shared.defaults.set(true, forKey: "shielded")
    }

    static func unshield() {
        ManagedSettingsStore(named: .whale).clearAllSettings()
        Shared.defaults.set(false, forKey: "shielded")
    }

    static var isShielded: Bool { Shared.defaults.bool(forKey: "shielded") }
}

/// 她说的话：用本地通知发出来（扩展里也能发）
enum Whisper {
    static func send(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
