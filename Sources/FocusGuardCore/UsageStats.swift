import Foundation

/// 某一天里某个网站或 App 用了多久
public struct UsageItem: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var isSite: Bool
    public var seconds: Double
    /// 按当前规则是否属于没营养的内容（规则改了，历史统计也跟着重新归类）
    public var isJunk: Bool
}

public struct DayTotal: Equatable, Identifiable {
    public var id: Date { day }
    public var day: Date
    public var seconds: Double
}

/// 每天每个网站 / App 的使用时长。key 形如 "site:bilibili.com"、"app:微信"。
public struct UsageStats: Codable, Equatable {
    /// "2026-10-20" → key → 秒数
    private var days: [String: [String: Double]] = [:]

    public init() {}

    /// 当前活动记在哪个名目下：浏览器记网站（命中规则时用规则本身，如 youtube.com/shorts），其他记 App 名
    public static func key(for activity: Activity, config: Config) -> String {
        if let url = activity.url {
            if let rule = Classifier.matchSite(url, rules: config.junkSites + config.forceCloseSites) {
                return "site:" + rule
            }
            if let site = Classifier.siteRule(from: url) {
                return "site:" + site
            }
        }
        return "app:" + activity.appName
    }

    public mutating func add(_ key: String, seconds: Double, at date: Date, calendar: Calendar = .current) {
        days[Self.dayKey(date, calendar), default: [:]][key, default: 0] += seconds
    }

    /// 某天的使用明细，按时长从多到少
    public func items(on date: Date, config: Config, calendar: Calendar = .current) -> [UsageItem] {
        (days[Self.dayKey(date, calendar)] ?? [:])
            .map { key, seconds in
                let isSite = key.hasPrefix("site:")
                let name = String(key.drop(while: { $0 != ":" }).dropFirst())
                return UsageItem(key: key, name: name, isSite: isSite, seconds: seconds,
                                 isJunk: Self.isJunk(name: name, isSite: isSite, config: config))
            }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
    }

    /// 最近 days 天每天的没营养总时长，从早到晚
    public func junkTotals(days count: Int, endingAt end: Date, config: Config,
                           calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: end)
        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let total = items(on: day, config: config, calendar: calendar)
                .filter(\.isJunk).reduce(0) { $0 + $1.seconds }
            return DayTotal(day: day, seconds: total)
        }
    }

    /// 只保留最近 keepingDays 天
    public mutating func prune(keepingDays: Int, now: Date, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: .day, value: -(keepingDays - 1), to: calendar.startOfDay(for: now))!
        let keep = Set((0..<keepingDays).map {
            Self.dayKey(calendar.date(byAdding: .day, value: $0, to: start)!, calendar)
        })
        days = days.filter { keep.contains($0.key) }
    }

    static func isJunk(name: String, isSite: Bool, config: Config) -> Bool {
        if isSite {
            let rules = config.junkSites + config.forceCloseSites
            return rules.contains(name) || Classifier.matchSite("https://" + name, rules: rules) != nil
        }
        return Classifier.junkReason(for: Activity(appName: name, bundleID: nil), config: config) != nil
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // MARK: - 读写

    public static var fileURL: URL {
        Config.fileURL.deletingLastPathComponent().appendingPathComponent("stats.json")
    }

    public static func load() -> UsageStats {
        (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.fileURL)
    }
}
