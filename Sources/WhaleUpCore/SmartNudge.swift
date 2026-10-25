import Foundation

/// 让大模型结合此刻的情况写劝导文案
public enum NudgePrompt {
    public static func make(nudge: Nudge, recentViews: [ContentView], reasons: [ReasonKind],
                            outcomes: String?, hourMinute: String, persona: String? = nil) -> (system: String, user: String) {
        // 有角色设定时用她的口吻说（劝导是桌宠说出来的）；没有就是一个了解他的朋友
        let who = persona.map { "下面是你的角色设定，劝导要用这个角色的口吻：\n\($0)\n\n" } ?? ""
        let system = who + """
            你是用户自己请来的注意力教练。用户正在电脑上刷没营养的内容，已经超过了他给自己定的时长，现在要弹一个小窗劝他停下来。
            请写一段劝导：像一个了解他的朋友，直接、具体、有温度，可以带一点幽默；用他刚才看的具体内容说话，不要说教，不要空话套话。
            他此刻坐在电脑前，劝导要符合这个场景：深夜劝他关掉网页、合上电脑去睡觉；白天劝他离开屏幕活动一下、休息眼睛，或者回到电脑上的正事。不要提手机。提醒次数越多，语气越认真。
            如果给出了“以前哪种劝法有效”，参考它调整说法。
            emoji 一个表情；title 不超过 8 个字；body 不超过 60 个字。
            """
        var lines = [
            "现在 \(hourMinute)，\(nudge.isNight ? "深夜" : "白天")。",
            "正在 \(nudge.reason.isEmpty ? nudge.appName : nudge.reason) 上，已经连续 \(nudge.sessionMinutes) 分钟，今天累计 \(nudge.todayMinutes) 分钟没营养的内容。",
            "这是这一轮的第 \(nudge.count) 次提醒。",
        ]
        if nudge.overBudget { lines.append("他给自己定的今日额度已经用完了。") }
        if nudge.isWorkTime { lines.append("现在是他设定的工作时间，应该回到工作上。") }
        let junk = recentViews.filter { $0.label?.isJunk ?? true }
        if !junk.isEmpty {
            lines.append("刚才看的（最近的在前）：")
            for v in junk.prefix(8) {
                var s = "- \(v.title)"
                if let l = v.label {
                    s += "（\(l.category)"
                    if let hook = l.hook, hook != "无" { s += "，靠\(hook)吸引人" }
                    s += "）"
                }
                lines.append(s)
            }
        }
        if !reasons.isEmpty {
            let counts = Dictionary(grouping: reasons, by: { $0 }).mapValues(\.count)
            lines.append("他最近被提醒时说的原因：" + ReasonKind.allCases.compactMap { k in counts[k].map { "\(k.label)×\($0)" } }
                .joined(separator: "，"))
        }
        if let outcomes { lines.append("以前的劝导效果：\(outcomes)") }
        return (system, lines.joined(separator: "\n"))
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["emoji": ["type": "string"], "title": ["type": "string"], "body": ["type": "string"]],
        "required": ["emoji", "title", "body"],
        "additionalProperties": false,
    ]

    public static func spec(_ p: (system: String, user: String), llm: LLMConfig) -> ChatSpec {
        // 用判断用的（快）模型，弹窗不能等太久
        ChatSpec(system: p.system, user: p.user, model: llm.taggingModel, maxTokens: 1024, effort: "low",
                 jsonSchema: schema, jsonExample: #"{"emoji": "🌙", "title": "该睡啦", "body": "……"}"#)
    }

    public static func parse(_ data: Data, provider: LLMProvider) throws -> NudgeText {
        struct Raw: Decodable { var emoji: String; var title: String; var body: String }
        let raw = try LLMResponse.jsonObject(Raw.self, from: try LLMResponse.text(data, provider: provider))
        let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = raw.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty, body.count <= 160 else { throw LLMError.badOutput(raw.body) }
        let emoji = raw.emoji.trimmingCharacters(in: .whitespaces)
        return NudgeText(emoji: emoji.isEmpty ? "☕️" : String(emoji.prefix(2)), title: String(title.prefix(16)), body: body)
    }
}
