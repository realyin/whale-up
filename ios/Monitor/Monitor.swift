import DeviceActivity
import Foundation

/// 系统在后台叫醒的计时扩展：新的一天解锁，快到时限提醒，到时限锁上
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // 新的一天（凌晨 4 点）：解锁，前一天加的时间作废
        if activity == .daily {
            Limiter.unshield()
            DeviceActivityCenter().stopMonitoring([.extra])
        }
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let s = LimitSettings.load()
        switch event {
        case .warn:
            Whisper.send("大肥鱼盯着你呢", "今天的 \(s.dailyMinutes) 分钟只剩 5 分钟了哦。")
        case .limit, .extraDone:
            Limiter.shield(s)
            Whisper.send("看我的魔法！", "今天刷够了，大肥鱼已经把它们关上了。明天凌晨 \(s.dayStartHour) 点再见～")
        default:
            break
        }
    }
}
