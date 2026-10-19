import Foundation

/// 记录哪些网页的内容（标题、作者、标签、观看时长）用于分析
public enum ContentScope: String, Codable, CaseIterable {
    /// 不记录
    case off
    /// 只记录没营养网站和强制关闭网站
    case junk
    /// 记录所有网页
    case all
}

public enum LLMProvider: String, Codable, CaseIterable {
    case anthropic
    /// 任何兼容 OpenAI Chat Completions 的接口
    case openai
    /// 本机 Ollama，内容不出电脑
    case ollama
}

/// 大模型设置。API Key 存钥匙串，不在这里。
public struct LLMConfig: Codable, Equatable {
    public var provider: LLMProvider = .anthropic
    /// 给单条内容打标签（量大，用小模型）
    public var taggingModel = "claude-haiku-5-5"
    /// 写日报 / 周报（用强模型）
    public var reportModel = "claude-opus-5-5"
    /// 留空用服务商默认地址
    public var baseURL = ""

    public init() {}

    public init(provider: LLMProvider, taggingModel: String, reportModel: String, baseURL: String) {
        self.provider = provider
        self.taggingModel = taggingModel
        self.reportModel = reportModel
        self.baseURL = baseURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LLMConfig()
        provider = try c.decodeIfPresent(LLMProvider.self, forKey: .provider) ?? d.provider
        taggingModel = try c.decodeIfPresent(String.self, forKey: .taggingModel) ?? d.taggingModel
        reportModel = try c.decodeIfPresent(String.self, forKey: .reportModel) ?? d.reportModel
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
    }
}

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

    /// 强制关闭模式：在这些网站上连续看满 forceCloseMinutes 分钟，直接关掉当前网页；
    /// 之后 forceCloseCooldownMinutes 分钟内再打开这些网站，会被立刻关掉
    public var forceCloseEnabled = false
    public var forceCloseMinutes: Double = 30
    public var forceCloseCooldownMinutes: Double = 15
    public var forceCloseSites: [String] = [
        "douyin.com", "kuaishou.com", "bilibili.com", "tiktok.com", "youtube.com/shorts",
    ]

    /// 内容记录范围
    public var contentScope: ContentScope = .junk
    /// 大模型（第 2 阶段起使用）
    public var llm = LLMConfig()

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
        forceCloseEnabled = try c.decodeIfPresent(Bool.self, forKey: .forceCloseEnabled) ?? d.forceCloseEnabled
        forceCloseMinutes = try c.decodeIfPresent(Double.self, forKey: .forceCloseMinutes) ?? d.forceCloseMinutes
        forceCloseCooldownMinutes = try c.decodeIfPresent(Double.self, forKey: .forceCloseCooldownMinutes) ?? d.forceCloseCooldownMinutes
        forceCloseSites = try c.decodeIfPresent([String].self, forKey: .forceCloseSites) ?? d.forceCloseSites
        contentScope = try c.decodeIfPresent(ContentScope.self, forKey: .contentScope) ?? d.contentScope
        llm = try c.decodeIfPresent(LLMConfig.self, forKey: .llm) ?? d.llm
    }

    /// 这个网页的内容要不要记录下来
    public func shouldRecordContent(url: String) -> Bool {
        switch contentScope {
        case .off: return false
        case .all: return Classifier.siteRule(from: url) != nil
        case .junk: return Classifier.matchSite(url, rules: junkSites + forceCloseSites) != nil
        }
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
