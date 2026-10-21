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
    /// 今天手动加的时间（秒）
    public private(set) var extraSeconds: Double = 0
    var day = ""
    var warned = false

    static let warnAheadSeconds: Double = 60

    public init() {}

    /// 今天能看多久（秒）
    public func limitSeconds(config: Config) -> Double { config.forceCloseMinutes * 60 + extraSeconds }

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

    /// 手动给今天加时间
    public mutating func grant(minutes: Double, now: Date = Date(), calendar: Calendar = .current) {
        rollDay(now, calendar)
        extraSeconds += minutes * 60
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
        warned = false
    }
}
