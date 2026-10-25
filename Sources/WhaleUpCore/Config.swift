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
    /// DeepSeek（兼容 OpenAI 格式，但只支持 json_object 输出模式）
    case deepseek
    /// 本机 Ollama，内容不出电脑
    case ollama
}

/// 大模型设置。API Key 存钥匙串，不在这里。
public struct LLMConfig: Codable, Equatable {
    /// 是否让大模型判断内容有没有营养（判断结果会覆盖“整个网站都算没营养”的规则）
    public var enabled = false
    /// 你自己对“有营养 / 没营养”的看法，会写进提示词
    public var preferences = "学习、技术、编程、英语、知识科普、纪录片、新闻深度分析算有营养；娱乐八卦、搞笑段子、情感纠纷、无脑短剧、游戏直播切片、猎奇和吵架类内容算没营养。"
    /// 劝导弹窗的文案由大模型结合此刻情况来写（失败或超时用固定文案）
    public var smartNudges = true
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
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        preferences = try c.decodeIfPresent(String.self, forKey: .preferences) ?? d.preferences
        smartNudges = try c.decodeIfPresent(Bool.self, forKey: .smartNudges) ?? d.smartNudges
        provider = try c.decodeIfPresent(LLMProvider.self, forKey: .provider) ?? d.provider
        taggingModel = try c.decodeIfPresent(String.self, forKey: .taggingModel) ?? d.taggingModel
        reportModel = try c.decodeIfPresent(String.self, forKey: .reportModel) ?? d.reportModel
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
    }
}

/// 用户可编辑的规则，保存在 ~/Library/Application Support/WhaleUp/config.json。
/// 缺少的字段使用默认值，方便只改自己关心的几项。
public struct Config: Codable, Equatable {
    /// 连续刷多久（分钟）后提醒：白天 / 夜间
    public var daytimeLimitMinutes: Double = 20
    public var nightLimitMinutes: Double = 5
    /// 夜间时段 [nightStartHour, nightEndHour)，可跨零点
    public var nightStartHour: Int = 23
    public var nightEndHour: Int = 6
    /// 工作时段：更严格，连续 workLimitMinutes 分钟就提醒。workDays 用 Calendar 的 weekday（1 = 周日，2 = 周一…）
    public var workHoursEnabled = false
    public var workDays = [2, 3, 4, 5, 6]
    public var workStartHour = 9
    public var workEndHour = 18
    public var workLimitMinutes: Double = 3
    /// 每天没营养内容的额度（分钟），0 = 不限。用完后再刷 1 分钟就提醒
    public var dailyBudgetMinutes: Double = 0
    /// 额度用完后直接关掉没营养的网页
    public var budgetCloses = false
    /// 桌宠：屏幕上的二次元角色，代替弹窗提醒，并用法术关网页
    public var mascotEnabled = true
    /// 桌宠说话时读出来（系统中文语音）
    public var mascotVoice = true
    /// 桌宠的声音（微软在线语音的名字，system 为系统语音）
    public var mascotVoiceName = "zh-CN-XiaoyiNeural"
    /// 桌宠自己按时做小动作（饭点吃饭、离开时睡觉、坐久了伸懒腰、偶尔打哈欠）
    public var mascotAutoActions = true
    /// 桌宠角色（Application Support/WhaleUp/Mascot/characters 下的文件夹名）
    public var mascotCharacter = "whale"
    /// 逐级加强：第二次提醒起“再刷”要等倒计时，第三次起还要写理由
    public var frictionEnabled = true
    public var frictionWaitSeconds = 10
    /// 从正常内容切到没营养的内容时，先停一下（10 分钟内最多一次）
    public var pauseBeforeJunk = false
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

    /// 强制关闭模式：今天在这些网站上累计看满 forceCloseMinutes 分钟，直接关掉当前网页；
    /// 当天之后不管什么时候再打开都会被立刻关掉。想多看只能在设置里手动给今天加时间
    public var forceCloseEnabled = false
    public var forceCloseMinutes: Double = 30
    public var forceCloseSites: [String] = [
        "douyin.com", "kuaishou.com", "bilibili.com", "tiktok.com", "youtube.com/shorts",
    ]
    /// 整站都算没营养的网站（如虎扑）：不看 AI 判断、首页也算，整个网站一起管
    public var wholeSites: [String] = []

    /// 只拦视频的网站（如推特）：不计时、不提醒；点开的视频被 AI 判为没营养就退回上一页。
    /// 同一个网站也在上面几个名单里时，按那几个名单算（所以往这里加网站不会放松管控）
    public var videoOnlySites: [String] = []

    /// 这个网址是不是按“只拦视频”管（不在其他名单里）
    public func isVideoOnlySite(_ url: String) -> Bool {
        Classifier.matchSite(url, rules: videoOnlySites) != nil && Classifier.matchSite(url, rules: watchedSites) == nil
    }

    /// 所有按网站管的规则：没营养的、强制关闭的、整站算的
    public var watchedSites: [String] { junkSites + forceCloseSites + wholeSites }

    /// 这个网址是不是“整站都算”的网站
    public func isWholeSite(_ url: String) -> Bool { Classifier.matchSite(url, rules: wholeSites) != nil }

    /// 内容记录范围
    public var contentScope: ContentScope = .junk
    /// 永不记录的敏感网站（银行、支付、邮箱、医疗、政务、密码管理）：连标题都不记，时长统计里也不显示网站名
    public var sensitiveSites: [String] = [
        "icbc.com.cn", "ccb.com", "abchina.com", "boc.cn", "bankcomm.com", "cmbchina.com", "psbc.com",
        "citicbank.com", "spdb.com.cn", "cib.com.cn", "cebbank.com", "pingan.com", "webank.com",
        "alipay.com", "paypal.com", "pay.weixin.qq.com",
        "mail.google.com", "mail.qq.com", "exmail.qq.com", "mail.163.com", "mail.126.com",
        "outlook.live.com", "outlook.office.com", "icloud.com",
        "haodf.com", "guahao.com", "dxy.com", "chunyuyisheng.com",
        "gov.cn", "1password.com", "bitwarden.com",
    ]
    /// 大模型
    public var llm = LLMConfig()
    /// 每天几点自动写当天的小结（需要开启 AI 判断）
    public var digestHour = 22
    /// 一天从几点开始算：这之前的都算前一天（晚上刷到凌晨不会被拆成两天）
    public var dayStartHour = 4
    /// 小结和每周复盘同时写进 Obsidian
    public var writeToObsidian = true
    /// 写到哪个文件夹；留空 = 自动找到 Obsidian 当前的库，在里面建“鲸醒”文件夹
    public var obsidianFolder = ""

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
        workHoursEnabled = try c.decodeIfPresent(Bool.self, forKey: .workHoursEnabled) ?? d.workHoursEnabled
        workDays = try c.decodeIfPresent([Int].self, forKey: .workDays) ?? d.workDays
        workStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? d.workStartHour
        workEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? d.workEndHour
        workLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .workLimitMinutes) ?? d.workLimitMinutes
        dailyBudgetMinutes = try c.decodeIfPresent(Double.self, forKey: .dailyBudgetMinutes) ?? d.dailyBudgetMinutes
        budgetCloses = try c.decodeIfPresent(Bool.self, forKey: .budgetCloses) ?? d.budgetCloses
        mascotEnabled = try c.decodeIfPresent(Bool.self, forKey: .mascotEnabled) ?? d.mascotEnabled
        mascotVoice = try c.decodeIfPresent(Bool.self, forKey: .mascotVoice) ?? d.mascotVoice
        mascotCharacter = try c.decodeIfPresent(String.self, forKey: .mascotCharacter) ?? d.mascotCharacter
        mascotAutoActions = try c.decodeIfPresent(Bool.self, forKey: .mascotAutoActions) ?? d.mascotAutoActions
        mascotVoiceName = try c.decodeIfPresent(String.self, forKey: .mascotVoiceName) ?? d.mascotVoiceName
        frictionEnabled = try c.decodeIfPresent(Bool.self, forKey: .frictionEnabled) ?? d.frictionEnabled
        frictionWaitSeconds = try c.decodeIfPresent(Int.self, forKey: .frictionWaitSeconds) ?? d.frictionWaitSeconds
        pauseBeforeJunk = try c.decodeIfPresent(Bool.self, forKey: .pauseBeforeJunk) ?? d.pauseBeforeJunk
        junkApps = try c.decodeIfPresent([String].self, forKey: .junkApps) ?? d.junkApps
        junkSites = try c.decodeIfPresent([String].self, forKey: .junkSites) ?? d.junkSites
        forceCloseEnabled = try c.decodeIfPresent(Bool.self, forKey: .forceCloseEnabled) ?? d.forceCloseEnabled
        forceCloseMinutes = try c.decodeIfPresent(Double.self, forKey: .forceCloseMinutes) ?? d.forceCloseMinutes
        forceCloseSites = try c.decodeIfPresent([String].self, forKey: .forceCloseSites) ?? d.forceCloseSites
        wholeSites = try c.decodeIfPresent([String].self, forKey: .wholeSites) ?? d.wholeSites
        videoOnlySites = try c.decodeIfPresent([String].self, forKey: .videoOnlySites) ?? d.videoOnlySites
        contentScope = try c.decodeIfPresent(ContentScope.self, forKey: .contentScope) ?? d.contentScope
        sensitiveSites = try c.decodeIfPresent([String].self, forKey: .sensitiveSites) ?? d.sensitiveSites
        llm = try c.decodeIfPresent(LLMConfig.self, forKey: .llm) ?? d.llm
        digestHour = try c.decodeIfPresent(Int.self, forKey: .digestHour) ?? d.digestHour
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
        writeToObsidian = try c.decodeIfPresent(Bool.self, forKey: .writeToObsidian) ?? d.writeToObsidian
        obsidianFolder = try c.decodeIfPresent(String.self, forKey: .obsidianFolder) ?? d.obsidianFolder
    }

    /// 这个网页的内容要不要记录下来
    public func shouldRecordContent(url: String) -> Bool {
        if isSensitive(url: url) { return false }
        switch contentScope {
        case .off: return false
        case .all: return Classifier.siteRule(from: url) != nil
        case .junk: return Classifier.matchSite(url, rules: watchedSites) != nil
        }
    }

    public func isSensitive(url: String) -> Bool {
        Classifier.matchSite(url, rules: sensitiveSites) != nil
    }

    public func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        if nightStartHour <= nightEndHour { return h >= nightStartHour && h < nightEndHour }
        return h >= nightStartHour || h < nightEndHour
    }

    public func isWorkTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard workHoursEnabled, workDays.contains(calendar.component(.weekday, from: date)) else { return false }
        let h = calendar.component(.hour, from: date)
        return h >= workStartHour && h < workEndHour
    }

    public func limitSeconds(at date: Date, calendar: Calendar = .current) -> Double {
        if isWorkTime(date, calendar: calendar) { return workLimitMinutes * 60 }
        return (isNight(date, calendar: calendar) ? nightLimitMinutes : daytimeLimitMinutes) * 60
    }

    /// 今天还剩多少额度；没设额度时为 nil
    public func budgetRemainingSeconds(usedToday: Double) -> Double? {
        guard dailyBudgetMinutes > 0 else { return nil }
        return max(0, dailyBudgetMinutes * 60 - usedToday)
    }

    // MARK: - 读写

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhaleUp/config.json")
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
