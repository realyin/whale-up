import Foundation

public enum ForceAction: Equatable {
    /// 还有 1 分钟就要关了
    case warn
    /// 现在关掉当前网页
    case close
}

/// 强制关闭模式：今天在名单网站上累计看满 forceCloseMinutes 分钟，直接关掉网页；
/// 之后当天不管什么时候再打开都立刻关掉。想多看只能手动给今天加时间（grant），不会过一会儿自己放开。
/// 累计时长由调用方从使用统计里算好传进来（和界面上看到的数字一致）。纯逻辑，不依赖系统 API。
public struct ForceCloser: Codable, Equatable {
    /// 今天手动调整的时间（秒）：正的是多看，负的是少看
    public private(set) var extraSeconds: Double = 0
    var day = ""
    var warned = false
    /// 今天“多看”了几次（每天最多 maxGrants 次）
    public private(set) var grantsToday = 0
    public static let maxGrants = 2

    static let warnAheadSeconds: Double = 60

    public init() {}

    // 老版本存的状态里没有新加的字段，缺的用默认值（否则整个读不出来，今天的调整就丢了）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        extraSeconds = try c.decodeIfPresent(Double.self, forKey: .extraSeconds) ?? 0
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        warned = try c.decodeIfPresent(Bool.self, forKey: .warned) ?? false
        grantsToday = try c.decodeIfPresent(Int.self, forKey: .grantsToday) ?? 0
    }

    /// 今天能看多久（秒）：每天的时长加上今天的调整，最少 5 分钟
    public func limitSeconds(config: Config) -> Double {
        max(Self.minimumSeconds, config.forceCloseMinutes * 60 + extraSeconds)
    }

    /// 今天最少能看 5 分钟、最多多看 3 小时
    static let minimumSeconds: Double = 5 * 60
    static let maximumExtraSeconds: Double = 3 * 3600

    /// 今天的时间用完了没有
    public func isBlocked(usedToday: Double, config: Config) -> Bool {
        config.forceCloseEnabled && usedToday >= limitSeconds(config: config)
    }

    /// 每次检测时调用。onSite：正在看名单里的网站；usedToday：今天在名单网站上累计看了多少秒
    public mutating func record(onSite: Bool, usedToday: Double, now: Date, config: Config,
                                calendar: Calendar = .current) -> ForceAction? {
        rollDay(now, calendar)
        guard config.forceCloseEnabled, onSite else { return nil }
        let limit = limitSeconds(config: config)
        if usedToday >= limit { return .close }
        if !warned, limit > Self.warnAheadSeconds, usedToday >= limit - Self.warnAheadSeconds {
            warned = true
            return .warn
        }
        return nil
    }

    /// 今天还能“多看”几次
    public func grantsLeft(now: Date = Date(), calendar: Calendar = .current) -> Int {
        DayKey.string(now, calendar: calendar) == day ? max(0, Self.maxGrants - grantsToday) : Self.maxGrants
    }

    /// 今天多看（正）或少看（负）几分钟，只管今天。多看每天最多 maxGrants 次，用完了返回 false
    @discardableResult
    public mutating func adjust(minutes: Double, config: Config, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        rollDay(now, calendar)
        if minutes > 0 {
            guard grantsToday < Self.maxGrants else { return false }
            grantsToday += 1
        }
        let lowest = Self.minimumSeconds - config.forceCloseMinutes * 60
        extraSeconds = min(Self.maximumExtraSeconds, max(lowest, extraSeconds + minutes * 60))
        warned = false
        return true
    }

    /// 恢复成每天的时长
    public mutating func resetToday(now: Date = Date(), calendar: Calendar = .current) {
        rollDay(now, calendar)
        extraSeconds = 0
        warned = false
    }

    /// 剩余可看秒数
    public func remainingSeconds(usedToday: Double, config: Config) -> Double {
        max(0, limitSeconds(config: config) - usedToday)
    }

    /// 新的一天（凌晨 dayStartHour 点起）：手动加的时间清零
    private mutating func rollDay(_ now: Date, _ calendar: Calendar) {
        let key = DayKey.string(now, calendar: calendar)
        guard key != day else { return }
        day = key
        extraSeconds = 0
        grantsToday = 0
        warned = false
    }
}
