import Foundation

/// 一段连续在同一个网站上的浏览（连划多个短视频合成一段）
public struct TimelineSession: Identifiable, Equatable {
    public var id: String { items.first?.viewId ?? site }
    public var site: String
    public var start: Double
    public var end: Double
    public var items: [ContentView]
    public var activeSeconds: Double { items.reduce(0) { $0 + $1.activeSeconds } }
    public var junkSeconds: Double
    /// 按时长多数决定这段算不算没营养
    public var isJunk: Bool { junkSeconds * 2 > activeSeconds }
}

public struct HourBucket: Identifiable, Equatable {
    public var id: Int { hour }
    public var hour: Int
    public var junkSeconds: Double
    public var goodSeconds: Double
}

public struct TimelineDay: Equatable {
    public var sessions: [TimelineSession]
    /// 0–23 点，每小时的有营养 / 没营养时长（按开始时间归入小时）
    public var hours: [HourBucket]
}

public enum Timeline {
    /// 同一网站两条记录间隔不超过这么久，算同一段
    static let mergeGap: Double = 5 * 60

    public static func build(views: [ContentView], config: Config, calendar: Calendar = .current) -> TimelineDay {
        var sessions: [TimelineSession] = []
        var hours = (0..<24).map { HourBucket(hour: $0, junkSeconds: 0, goodSeconds: 0) }

        for v in views.sorted(by: { $0.startedAt < $1.startedAt }) {
            let junk = v.isJunk(config: config)
            let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: v.startedAt))
            if junk { hours[hour].junkSeconds += v.activeSeconds } else { hours[hour].goodSeconds += v.activeSeconds }

            if var last = sessions.last, last.site == v.site, v.startedAt - last.end <= mergeGap {
                last.items.append(v)
                last.end = max(last.end, v.endedAt)
                if junk { last.junkSeconds += v.activeSeconds }
                sessions[sessions.count - 1] = last
            } else {
                sessions.append(TimelineSession(site: v.site, start: v.startedAt, end: max(v.endedAt, v.startedAt),
                                                items: [v], junkSeconds: junk ? v.activeSeconds : 0))
            }
        }
        return TimelineDay(sessions: sessions, hours: hours)
    }
}
