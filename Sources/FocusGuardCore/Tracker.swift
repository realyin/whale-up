import Foundation

/// 一次需要弹出的提醒
public struct Nudge: Equatable {
    public var reason: String
    public var appName: String
    public var sessionMinutes: Int
    public var todayMinutes: Int
    public var isNight: Bool
    /// 本次连续刷的过程中第几次提醒（用于语气逐步加重）
    public var count: Int

    public init(reason: String, appName: String, sessionMinutes: Int, todayMinutes: Int, isNight: Bool, count: Int) {
        self.reason = reason
        self.appName = appName
        self.sessionMinutes = sessionMinutes
        self.todayMinutes = todayMinutes
        self.isNight = isNight
        self.count = count
    }
}

/// 累计“没营养”时长，并决定什么时候提醒。纯逻辑，不依赖系统 API。
public struct Tracker: Codable, Equatable {
    /// 本次连续刷的秒数
    public private(set) var sessionSeconds: Double = 0
    /// 今天累计秒数
    public private(set) var todaySeconds: Double = 0
    public private(set) var nudgeCount = 0
    var dayKey = ""
    var lastJunkAt: Date?
    var nextNudgeAllowedAt: Date?

    public init() {}

    /// 每次检测时调用。elapsed 是距上次检测经过的秒数。
    /// 返回非 nil 表示现在应该提醒。
    public mutating func record(isJunk: Bool, isIdle: Bool, now: Date, elapsed: Double,
                                config: Config, calendar: Calendar = .current,
                                reason: String = "", appName: String = "") -> Nudge? {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let key = "\(c.year!)-\(c.month!)-\(c.day!)"
        if key != dayKey {
            dayKey = key
            todaySeconds = 0
        }

        guard isJunk, !isIdle else { return nil }

        if let last = lastJunkAt, now.timeIntervalSince(last) > config.sessionBreakMinutes * 60 {
            resetSession()
        }
        sessionSeconds += elapsed
        todaySeconds += elapsed
        lastJunkAt = now

        guard sessionSeconds >= config.limitSeconds(at: now, calendar: calendar) else { return nil }
        if let next = nextNudgeAllowedAt, now < next { return nil }

        nudgeCount += 1
        nextNudgeAllowedAt = now.addingTimeInterval(config.snoozeMinutes * 60)
        return Nudge(reason: reason, appName: appName,
                     sessionMinutes: Int(sessionSeconds / 60), todayMinutes: Int(todaySeconds / 60),
                     isNight: config.isNight(now, calendar: calendar), count: nudgeCount)
    }

    /// 用户接受了建议去休息：连续时长重新开始
    public mutating func acceptRest() {
        resetSession()
    }

    private mutating func resetSession() {
        sessionSeconds = 0
        nudgeCount = 0
        nextNudgeAllowedAt = nil
    }
}
