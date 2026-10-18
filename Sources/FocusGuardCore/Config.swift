import Foundation

/// 用户可编辑的规则，保存在 ~/Library/Application Support/FocusGuard/config.json。
/// 缺少的字段使用默认值，方便只改自己关心的几项。
public struct Config: Codable, Equatable {
    /// 连续刷多久（分钟）后提醒：白天 / 夜间
    public var daytimeLimitMinutes: Double = 20
    public var nightLimitMinutes: Double = 5
    /// 夜间时段 [nightStartHour, nightEndHour)，可跨零点
    public var nightStartHour: Int = 23
    public var nightEndHour: Int = 6
    /// 点了“再刷一会儿”后，多久再提醒
    public var snoozeMinutes: Double = 5
    /// 离开“没营养”内容超过这么久，连续时长清零
    public var sessionBreakMinutes: Double = 5
    /// 键鼠无操作超过这么久算人已离开，不计时（看长视频时可能长时间不动鼠标，所以不宜太短）
    public var idleSeconds: Double = 300
    /// 检测间隔
    public var checkIntervalSeconds: Double = 5

    /// 匹配 App 名称（包含即可，不区分大小写）或 Bundle ID（完全相同）
    public var junkApps: [String] = ["抖音", "Douyin", "快手", "小红书", "rednote", "微博", "哔哩哔哩", "bilibili", "TikTok"]
    /// 匹配浏览器网址：域名（含子域名），可带路径前缀，如 "youtube.com/shorts"
    public var junkSites: [String] = [
        "douyin.com", "kuaishou.com", "bilibili.com", "weibo.com", "xiaohongshu.com",
        "tiktok.com", "youtube.com/shorts", "x.com", "twitter.com", "reddit.com", "9gag.com",
    ]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        daytimeLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .daytimeLimitMinutes) ?? d.daytimeLimitMinutes
        nightLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .nightLimitMinutes) ?? d.nightLimitMinutes
        nightStartHour = try c.decodeIfPresent(Int.self, forKey: .nightStartHour) ?? d.nightStartHour
        nightEndHour = try c.decodeIfPresent(Int.self, forKey: .nightEndHour) ?? d.nightEndHour
        snoozeMinutes = try c.decodeIfPresent(Double.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        sessionBreakMinutes = try c.decodeIfPresent(Double.self, forKey: .sessionBreakMinutes) ?? d.sessionBreakMinutes
        idleSeconds = try c.decodeIfPresent(Double.self, forKey: .idleSeconds) ?? d.idleSeconds
        checkIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .checkIntervalSeconds) ?? d.checkIntervalSeconds
        junkApps = try c.decodeIfPresent([String].self, forKey: .junkApps) ?? d.junkApps
        junkSites = try c.decodeIfPresent([String].self, forKey: .junkSites) ?? d.junkSites
    }

    public func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        if nightStartHour <= nightEndHour { return h >= nightStartHour && h < nightEndHour }
        return h >= nightStartHour || h < nightEndHour
    }

    public func limitSeconds(at date: Date, calendar: Calendar = .current) -> Double {
        (isNight(date, calendar: calendar) ? nightLimitMinutes : daytimeLimitMinutes) * 60
    }

    // MARK: - 读写

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusGuard/config.json")
    }

    /// 读取配置；文件不存在时写出一份默认配置。解析失败返回错误信息，并沿用默认值。
    public static func load() -> (Config, error: String?) {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else {
            let config = Config()
            config.save()
            return (config, nil)
        }
        do {
            return (try JSONDecoder().decode(Config.self, from: data), nil)
        } catch {
            return (Config(), "配置文件格式有误，已使用默认规则：\(error.localizedDescription)")
        }
    }

    public func save() {
        let url = Config.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(self).write(to: url)
    }
}
