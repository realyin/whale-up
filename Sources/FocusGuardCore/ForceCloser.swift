import Foundation

public enum ForceAction: Equatable {
    /// 还有 1 分钟就要关了
    case warn
    /// 现在关掉当前网页
    case close
}

/// 强制关闭模式：在指定网站上连续停留太久，直接关掉网页；
/// 关掉后的冷却期内重新打开这些网站，也会被立刻关掉。纯逻辑，不依赖系统 API。
public struct ForceCloser: Codable, Equatable {
    public private(set) var sessionSeconds: Double = 0
    public private(set) var blockedUntil: Date?
    var lastSeenAt: Date?
    var warned = false

    static let warnAheadSeconds: Double = 60

    public init() {}

    public mutating func record(onSite: Bool, isIdle: Bool, now: Date, elapsed: Double, config: Config) -> ForceAction? {
        guard config.forceCloseEnabled, onSite else { return nil }

        if let until = blockedUntil {
            if now < until { return .close }
            blockedUntil = nil
        }
        guard !isIdle else { return nil }

        if let last = lastSeenAt, now.timeIntervalSince(last) > config.sessionBreakMinutes * 60 {
            sessionSeconds = 0
            warned = false
        }
        sessionSeconds += elapsed
        lastSeenAt = now

        let limit = config.forceCloseMinutes * 60
        if sessionSeconds >= limit {
            sessionSeconds = 0
            warned = false
            blockedUntil = now.addingTimeInterval(config.forceCloseCooldownMinutes * 60)
            return .close
        }
        if !warned, limit > Self.warnAheadSeconds, sessionSeconds >= limit - Self.warnAheadSeconds {
            warned = true
            return .warn
        }
        return nil
    }

    /// 剩余可看秒数（用于菜单显示）
    public func remainingSeconds(config: Config) -> Double {
        max(0, config.forceCloseMinutes * 60 - sessionSeconds)
    }
}
