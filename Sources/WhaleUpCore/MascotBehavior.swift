import Foundation

/// 桌宠的小动作什么时候做：离开时睡觉、回来时打哈欠、饭点吃大米饭、坐久了伸懒腰、偶尔打哈欠
public struct MascotBehavior: Equatable {
    public enum Action: String { case yawn, sleep, stretch, eat }

    public enum Event: Equatable {
        /// 开始一个动作；line 是要说的话（nil 不说）
        case start(Action, line: String?)
        case stop(Action)
    }

    /// 饭点（时, 分），开始后一小时内都算
    static let meals = [(11, 45), (18, 0)]
    static let stretchAfter: Double = 45 * 60

    var sleeping = false
    var activeSince: Date?
    var lastStretchAt: Date?
    var nextYawnAt: Date?
    var mealsDone: Set<String> = []

    public init() {}

    /// 每次检测时调用。jitter 是 0–1 的随机数，用来让打哈欠的间隔不那么规律
    public mutating func update(now: Date, idleSeconds: Double, isJunk: Bool, config: Config,
                                calendar: Calendar = .current, jitter: Double = .random(in: 0...1)) -> [Event] {
        var events: [Event] = []
        let away = idleSeconds >= config.idleSeconds

        // 离开电脑：睡觉；回来：醒来打哈欠
        if away {
            activeSince = nil
            if !sleeping {
                sleeping = true
                events.append(.start(.sleep, line: nil))
            }
            return events
        }
        if sleeping {
            sleeping = false
            events.append(.stop(.sleep))
            events.append(.start(.yawn, line: "你回来啦～"))
            nextYawnAt = now.addingTimeInterval(yawnInterval(now: now, config: config, calendar: calendar, jitter: jitter))
        }
        if activeSince == nil { activeSince = now }

        // 饭点：吃大米饭（每顿一次）
        let day = DayKey.string(now, calendar: calendar)
        for (h, m) in Self.meals {
            let key = "\(day) \(h):\(m)"
            guard let start = calendar.date(bySettingHour: h, minute: m, second: 0, of: now),
                  now >= start, now < start.addingTimeInterval(3600), !mealsDone.contains(key) else { continue }
            mealsDone.insert(key)
            events.append(.start(.eat, line: "到饭点啦，干饭去！🍚"))
            return events
        }

        // 连续用电脑太久：伸懒腰
        if let since = activeSince, now.timeIntervalSince(since) >= Self.stretchAfter,
           now.timeIntervalSince(lastStretchAt ?? .distantPast) >= Self.stretchAfter {
            lastStretchAt = now
            events.append(.start(.stretch, line: "坐了好久啦，一起伸个懒腰～"))
            return events
        }

        // 偶尔打哈欠（在刷没营养的内容时她在盯着你，不打）
        if nextYawnAt == nil {
            nextYawnAt = now.addingTimeInterval(yawnInterval(now: now, config: config, calendar: calendar, jitter: jitter))
        }
        if !isJunk, let next = nextYawnAt, now >= next {
            let night = config.isNight(now, calendar: calendar)
            events.append(.start(.yawn, line: night ? "好困……该睡了吧" : nil))
            nextYawnAt = now.addingTimeInterval(yawnInterval(now: now, config: config, calendar: calendar, jitter: jitter))
        }
        return events
    }

    /// 白天 20–40 分钟一次，夜里 8–15 分钟一次
    func yawnInterval(now: Date, config: Config, calendar: Calendar, jitter: Double) -> Double {
        config.isNight(now, calendar: calendar) ? (8 + 7 * jitter) * 60 : (20 + 20 * jitter) * 60
    }
}
