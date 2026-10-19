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
    public static func make(day: Date, views: [ContentView], reasons: [NudgeReason], config: Config,
                            calendar: Calendar = .current) -> (system: String, user: String) {
        let system = """
            你是用户的个人注意力教练。下面是用户某一天在电脑上看视频、刷网页的记录（由浏览器扩展和一个小助手自动记录）。
            请用中文写一份简短的每日小结，语气像一个关心他、但说话直接的朋友：不说教，不空泛，用记录里的具体内容说话。

            用 Markdown，按下面的小标题写，总共不超过 400 字：
            ## 今天概况
            两三句话：刷了多久、和有营养的内容比起来怎么样。
            ## 往脑子里装了什么
            诚实地概括今天看的没营养内容主要是什么（主题、风格、吸引人的点），以及有营养的内容学到了什么。
            ## 什么时候最容易刷
            结合时间分布和用户自己说的原因，指出触发场景（比如深夜、累了、在逃避某件事）。
            ## 明天试试
            一个具体、容易做到的小建议，针对今天发现的模式。

            如果记录很少，就简短地写，不要编造记录里没有的内容。
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
