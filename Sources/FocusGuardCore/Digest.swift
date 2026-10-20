import Foundation

/// 某一天的小结
public struct Digest: Equatable {
    public var day: String
    public var text: String
    public var model: String
    public var createdAt: Double

    public init(day: String, text: String, model: String, createdAt: Double = Date().timeIntervalSince1970) {
        self.day = day
        self.text = text
        self.model = model
        self.createdAt = createdAt
    }
}

public enum DayKey {
    /// "2026-10-20"
    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        UsageStats.dayKey(date, calendar)
    }
}

extension ContentView {
    /// 按网站规则和大模型判断，这条内容算不算没营养
    public func isJunk(config: Config) -> Bool {
        let ruleMatched = Classifier.matchSite(url, rules: config.junkSites + config.forceCloseSites) != nil
        return JunkJudge.isJunk(siteRuleMatched: ruleMatched, label: label, config: config)
    }
}

/// 写每日小结的提示词。数据都在本机整理好，只把整理后的文字发给大模型。
public enum DigestPrompt {
    public static func make(day: Date, views: [ContentView], reasons: [NudgeReason], nudges: [NudgeRecord] = [],
                            config: Config, calendar: Calendar = .current) -> (system: String, user: String) {
        let system = """
            你是用户的注意力教练。下面是用户某一天看视频、刷网页的记录。界面上已经用图表显示了时长和分布，你只负责给出洞察。

            输出要求：
            - headline：一句话结论，不超过 20 字，点出今天最值得注意的一件事。
            - findings：最多 3 条发现，每条不超过 30 字。每条是一个判断（规律、对比、触发场景），用记录里的具体内容或用户自己说的原因作依据；不要只罗列时间和事件。没有值得说的就少写，可以是空数组。
            - tomorrow：明天的一个具体行动，不超过 25 字，针对今天的发现。

            不要复述总时长等界面已有的数字；不要猜测心理动机，除非用户自己说过原因；不要客套、鼓励、感叹号；不要编造记录里没有的内容。

            \(Suggestion.guide(for: config))
            """

        let byTime = views.sorted { $0.startedAt < $1.startedAt }
        let junk = byTime.filter { $0.isJunk(config: config) }
        let junkSeconds = junk.reduce(0) { $0 + $1.activeSeconds }
        let goodSeconds = byTime.filter { !$0.isJunk(config: config) }.reduce(0) { $0 + $1.activeSeconds }

        var hours: [Int: Double] = [:]
        for v in junk {
            hours[calendar.component(.hour, from: Date(timeIntervalSince1970: v.startedAt)), default: 0] += v.activeSeconds
        }
        let hourLine = hours.keys.sorted().map { "\($0) 点 \(minutes(hours[$0]!))" }.joined(separator: "，")

        var lines = [
            "日期：\(DayKey.string(day, calendar: calendar))",
            "没营养内容共 \(minutes(junkSeconds))，有营养内容共 \(minutes(goodSeconds))，共 \(byTime.count) 条记录。",
            "没营养内容的时间分布：\(hourLine.isEmpty ? "无" : hourLine)",
        ]
        if !reasons.isEmpty {
            let text = reasons.sorted { $0.at < $1.at }.map {
                "\(Self.time($0.at.timeIntervalSince1970, calendar)) \($0.reason.label)（在 \($0.site)，已连续 \($0.sessionMinutes) 分钟）"
            }
            lines.append("被提醒时用户自己说的原因：" + text.joined(separator: "；"))
        }
        if let summary = NudgeRecord.summary(nudges) { lines.append("今天的劝导：" + summary) }
        lines.append("\n看过的内容（按时间先后，🍟 没营养，🥦 有营养）：")
        for v in byTime.suffix(120) {
            var parts = ["\(time(v.startedAt, calendar)) \(v.isJunk(config: config) ? "🍟" : "🥦") \(v.site)", v.title]
            if let a = v.author, !a.isEmpty { parts.append("作者 \(a)") }
            parts.append("看了 \(minutes(v.activeSeconds))")
            if v.backgroundSeconds >= 60 { parts.append("其中后台播放 \(minutes(v.backgroundSeconds))") }
            if let l = v.label {
                var judged = "\(l.category) \(l.nutrition)/5"
                if let hook = l.hook, hook != "无" { judged += " 钩子：\(hook)" }
                parts.append(judged)
            } else if !v.tags.isEmpty {
                parts.append("标签 " + v.tags.prefix(4).joined(separator: "、"))
            }
            lines.append("- " + parts.joined(separator: " · "))
        }
        return (system, lines.joined(separator: "\n"))
    }

    static func minutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 60 ? "\(m) 分钟" : "\(m / 60) 小时 \(m % 60) 分钟"
    }

    static func time(_ t: Double, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
}

/// 每日小结的结构化内容（界面按卡片展示，Obsidian 里写成简短 Markdown）
public struct DailyReport: Codable, Equatable {
    public var headline: String
    public var findings: [String]
    public var tomorrow: String
    /// 可以一键生效的设置（没有为 nil）
    public var setting: Suggestion?

    public init(headline: String, findings: [String], tomorrow: String, setting: Suggestion? = nil) {
        self.headline = headline
        self.findings = findings
        self.tomorrow = tomorrow
        self.setting = setting
    }

    public static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "findings": ["type": "array", "items": ["type": "string"]],
            "tomorrow": ["type": "string"],
            "setting": Suggestion.schema,
        ],
        "required": ["headline", "findings", "tomorrow", "setting"],
        "additionalProperties": false,
    ]
    public static let example = #"{"headline": "深夜刷抖音是今天唯一的失守", "findings": ["23 点后连看 8 个搞笑视频", "Swift 教程看了 18 分钟"], "tomorrow": "23:00 后抖音每次只给 10 分钟", "setting": {"kind": "nightLimit", "site": "", "minutes": 10}}"#

    public static func parse(_ text: String) throws -> DailyReport {
        var r = try LLMResponse.jsonObject(DailyReport.self, from: text)
        r.findings = Array(r.findings.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(3))
        return r
    }

    public var markdown: String {
        var parts = ["**\(headline)**"]
        if !findings.isEmpty { parts.append(findings.map { "- \($0)" }.joined(separator: "\n")) }
        parts.append("明天：\(tomorrow)")
        return parts.joined(separator: "\n\n")
    }

    public var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }
}

extension Digest {
    /// 新格式的每日小结；旧的 Markdown 格式返回 nil
    public var daily: DailyReport? { try? DailyReport.parse(text) }
    public var weekly: WeeklyReport? { day.contains("W") ? try? WeeklyReport.parse(text) : nil }
}
