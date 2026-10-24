import Foundation

/// 今天每个 App / 网站刷了多久，和每天的设置。存在 App Group 里，鲸醒 App 和 Safari 扩展读写同一份：
/// 每天的时长、今天多看少看、要管的网站都只有一个，App 和 Safari 里刷的时间也加在一起算。
struct Usage: Codable {
    static let group = "group.io.github.realyin.whaleup.lite"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    var limit = 30
    var dayStartHour = 4
    var day = ""
    /// 名目 → 秒数：App 名字（“抖音”），或 Safari 里的网站（“Safari · douyin.com”）
    var seconds: [String: Double] = [:]
    /// 正在刷的 App 和开始时间（还没收到“刷完了”）
    var open: [String: Date] = [:]
    var extraDay = ""
    /// 今天多看（正）或少看（负）几分钟，只管今天
    var extra = 0
    /// Safari 扩展管哪些网站
    var sites = ["douyin.com", "bilibili.com", "b23.tv", "youtube.com", "kuaishou.com", "xiaohongshu.com",
                 "weibo.com", "weibo.cn", "tiktok.com", "ixigua.com", "toutiao.com"]

    /// 一次最多算 2 小时：手机重启、自动化没跑等情况下，不会一直算下去
    static let maxSession: Double = 2 * 3600
    private static let key = "usage"

    init() {}

    // 老版本存的数据里没有 sites 等字段，缺的用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Usage()
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? d.limit
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? d.day
        seconds = try c.decodeIfPresent([String: Double].self, forKey: .seconds) ?? d.seconds
        open = try c.decodeIfPresent([String: Date].self, forKey: .open) ?? d.open
        extraDay = try c.decodeIfPresent(String.self, forKey: .extraDay) ?? d.extraDay
        extra = try c.decodeIfPresent(Int.self, forKey: .extra) ?? d.extra
        sites = try c.decodeIfPresent([String].self, forKey: .sites) ?? d.sites
    }

    static func load() -> Usage {
        // 开发用：用 -demo 启动时给一份示例数据，截图看界面
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            var d = Usage()
            d.day = d.dayKey(); d.extraDay = d.day
            d.seconds = ["抖音": 14 * 60, "Safari · youtube.com": 5 * 60]
            d.open = ["B 站": Date().addingTimeInterval(-3 * 60)]
            return d
        }
        // 第一次用 App Group 时，把以前存在 App 自己那里的数据搬过来
        let data = defaults.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        var u = data.flatMap { try? JSONDecoder().decode(Usage.self, from: $0) } ?? Usage()
        let today = u.dayKey()
        if u.day != today {
            u.day = today
            u.seconds = [:]
            u.open = [:]
        }
        if u.extraDay != today { u.extraDay = today; u.extra = 0 }
        return u
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Self.defaults.set(data, forKey: Self.key) }
    }

    /// 凌晨 dayStartHour 点以前算前一天
    func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-Double(dayStartHour) * 3600))
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func usedSeconds(_ name: String, now: Date = Date()) -> Double {
        (seconds[name] ?? 0) + (open[name].map { min(Self.maxSession, now.timeIntervalSince($0)) } ?? 0)
    }

    var used: Double {
        Set(seconds.keys).union(open.keys).reduce(0) { $0 + usedSeconds($1) }
    }

    /// 今天一共能刷几分钟（每天的时长加上今天的调整，最少 5 分钟）
    var todayLimit: Int { max(5, limit + extra) }
    var limitSeconds: Double { Double(todayLimit) * 60 }
    var isOver: Bool { used >= limitSeconds }
    var leftSeconds: Double { max(0, limitSeconds - used) }

    mutating func start(_ app: String) {
        stop(app)
        open[app] = Date()
    }

    mutating func stop(_ app: String) {
        guard let started = open.removeValue(forKey: app) else { return }
        seconds[app, default: 0] += min(Self.maxSession, Date().timeIntervalSince(started))
    }

    /// 今天多看 / 少看：今天最少 5 分钟，最多多看 3 小时
    mutating func adjust(_ minutes: Int) {
        extra = min(180, max(5 - limit, extra + minutes))
    }

    mutating func setLimit(_ value: Int) {
        limit = min(240, max(5, value))
        extra = max(5 - limit, extra)
    }

    static let safariPrefix = "Safari · "

    /// App 自己记的秒数（抖音等 App，不含 Safari 扩展报过来的网页时间）
    var appUsed: Double {
        Set(seconds.keys).union(open.keys).filter { !$0.hasPrefix(Self.safariPrefix) }.reduce(0) { $0 + usedSeconds($1) }
    }

    /// 给 Safari 扩展的：App 自己记的时间和设置（Safari 的时间以扩展那边为准）
    var snapshot: [String: Any] {
        ["used": used, "appUsed": appUsed, "limit": limit, "extra": extra, "dayStartHour": dayStartHour, "sites": sites]
    }
}
