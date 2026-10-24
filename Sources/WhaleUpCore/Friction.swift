import Foundation

/// 逐级加强干预：提醒次数越多，想继续刷的门槛越高
public enum Friction: Equatable {
    /// “再刷一会儿”可以直接点
    case none
    /// 要等倒计时结束才能点
    case wait(seconds: Int)
    /// 先写一句为什么还要继续，再等倒计时
    case writeReason(waitSeconds: Int)

    public static func level(for nudge: Nudge, config: Config) -> Friction {
        guard config.frictionEnabled else { return .none }
        let wait = config.frictionWaitSeconds
        if nudge.overBudget || nudge.count >= 3 { return .writeReason(waitSeconds: wait) }
        if nudge.count == 2 { return .wait(seconds: wait) }
        return .none
    }

    /// 理由至少要写几个字，不能随便敷衍
    public static func isAcceptableReason(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }
}

/// “打开前先停一下”：从正常内容切到没营养的内容时拦一下
public enum PauseGate {
    public static func shouldPause(wasJunk: Bool, isJunk: Bool, lastPauseAt: Date?, now: Date, config: Config) -> Bool {
        guard config.pauseBeforeJunk, isJunk, !wasJunk else { return false }
        if let last = lastPauseAt, now.timeIntervalSince(last) < 600 { return false }
        return true
    }
}
