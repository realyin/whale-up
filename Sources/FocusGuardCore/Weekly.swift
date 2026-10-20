import Foundation

/// 一个 ISO 周（周一到周日）
public struct Week: Equatable {
    public var start: Date
    public var key: String

    public init(containing date: Date, calendar: Calendar = Week.calendar) {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        start = cal.date(from: c)!
        key = String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }

    public static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    public var days: [Date] { (0..<7).map { start.addingTimeInterval(Double($0) * 86400 + 3600) } }

    public var end: Date { start.addingTimeInterval(7 * 86400) }

    public func previous(calendar: Calendar = Week.calendar) -> Week {
        Week(containing: start.addingTimeInterval(-86400 * 3), calendar: calendar)
    }
}

/// 一周里某一天的材料
public struct WeekDay {
    public var day: Date
    public var views: [ContentView]
    public var reasons: [ReasonKind]
    public var nudges: [NudgeRecord]
    public var digest: String?

    public init(day: Date, views: [ContentView], reasons: [ReasonKind], nudges: [NudgeRecord], digest: String?) {
        self.day = day
        self.views = views
        self.reasons = reasons
        self.nudges = nudges
        self.digest = digest
    }
}

public enum WeeklyPrompt {
    public static func make(week: Week, days: [WeekDay], config: Config,
                            calendar: Calendar = .current) -> (system: String, user: String) {
        let system = """
            你是用户的注意力教练。下面是用户一周看视频、刷网页的汇总和每天的小结。界面上已经显示了时长图表，你只负责给出洞察和行动。

            输出要求：
            - headline：一句话结论，不超过 20 字。
            - patterns：最多 3 条规律（什么时间、什么情况、什么内容最容易刷），每条不超过 30 字，是归纳出的判断而不是流水账，必须有记录支撑。
            - cause：背后的原因，不超过 40 字。只引用用户自己说过的原因和内容的“钩子”，不要猜测心理动机；没有依据就写空字符串。
            - actions：最多 2 条具体行动，每条不超过 30 字。
            - alternative：根据他爱看的主题推荐一个有营养的替代方向，不超过 30 字；没有合适的就写空字符串。
            - commitment：下周一个可检查的承诺，不超过 25 字。

            不要复述总时长；不要客套、鼓励、感叹号；不要编造记录里没有的内容；记录少就少写。
            """
        let all = days.flatMap(\.views)
        let junk = all.filter { $0.isJunk(config: config) }
        let good = all.filter { !$0.isJunk(config: config) }
        func total(_ vs: [ContentView]) -> Double { vs.reduce(0) { $0 + $1.activeSeconds } }

        var lines = [
            "周：\(week.key)（\(DayKey.string(week.start, calendar: calendar)) 起）",
            "本周没营养共 \(DigestPrompt.minutes(total(junk)))，有营养共 \(DigestPrompt.minutes(total(good)))。",
        ]

        func top(_ pairs: [(String, Double)], _ n: Int) -> String {
            Dictionary(pairs, uniquingKeysWith: +).sorted { $0.value > $1.value }.prefix(n)
                .map { "\($0.key) \(DigestPrompt.minutes($0.value))" }.joined(separator: "，")
        }
        let categories = top(junk.compactMap { v in v.label.map { ($0.category, v.activeSeconds) } }, 6)
        if !categories.isEmpty { lines.append("没营养内容的主题：\(categories)") }
        let hooks = top(junk.compactMap { v in v.label?.hook.flatMap { $0 == "无" ? nil : ($0, v.activeSeconds) } }, 5)
        if !hooks.isEmpty { lines.append("吸引他的钩子：\(hooks)") }
        lines.append("没营养内容最多的网站：\(top(junk.map { ($0.site, $0.activeSeconds) }, 5))")

        var hours: [Int: Double] = [:]
        for v in junk { hours[calendar.component(.hour, from: Date(timeIntervalSince1970: v.startedAt)), default: 0] += v.activeSeconds }
        let hourText = hours.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key) 点 \(DigestPrompt.minutes($0.value))" }.joined(separator: "，")
        if !hourText.isEmpty { lines.append("最容易刷的时段：\(hourText)") }

        let reasons = days.flatMap(\.reasons)
        if !reasons.isEmpty {
            let counts = Dictionary(grouping: reasons, by: { $0 }).mapValues(\.count)
            lines.append("被提醒时他说的原因：" + ReasonKind.allCases.compactMap { k in counts[k].map { "\(k.label)×\($0)" } }
                .joined(separator: "，"))
        }
        if let summary = NudgeRecord.summary(days.flatMap(\.nudges)) { lines.append("本周的劝导：" + summary) }

        let goodTitles = good.sorted { $0.activeSeconds > $1.activeSeconds }.prefix(8).map(\.title)
        if !goodTitles.isEmpty { lines.append("有营养的内容：" + goodTitles.joined(separator: "；")) }
        let junkTitles = junk.sorted { $0.activeSeconds > $1.activeSeconds }.prefix(12).map(\.title)
        if !junkTitles.isEmpty { lines.append("看得最久的没营养内容：" + junkTitles.joined(separator: "；")) }

        lines.append("\n每天：")
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        for d in days {
            let name = weekdays[calendar.component(.weekday, from: d.day) - 1]
            let j = d.views.filter { $0.isJunk(config: config) }
            var line = "- \(name) \(DayKey.string(d.day, calendar: calendar))：没营养 \(DigestPrompt.minutes(total(j)))"
            if let digest = d.digest { line += "。当天小结：" + digest.replacingOccurrences(of: "\n", with: " ").prefix(400) }
            lines.append(line)
        }
        return (system, lines.joined(separator: "\n"))
    }
}

/// 写进 Obsidian 的笔记
public enum ObsidianNote {
    public static func render(title: String, kind: String, date: String, body: String) -> String {
        """
        ---
        tags: [专注守护, \(kind)]
        date: \(date)
        ---

        # \(title)

        \(body)

        """
    }

    /// 从 Obsidian 的配置里找库：优先当前打开的，否则第一个
    public static func openVault(fromConfig data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: [String: Any]] else { return nil }
        let list = vaults.values.sorted { ($0["ts"] as? Double ?? 0) < ($1["ts"] as? Double ?? 0) }
        return (list.first { $0["open"] as? Bool == true } ?? list.first)?["path"] as? String
    }

    /// 本机 Obsidian 当前的库
    public static func detectVault() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        return (try? Data(contentsOf: url)).flatMap(openVault(fromConfig:))
    }
}

/// 每周复盘的结构化内容
public struct WeeklyReport: Codable, Equatable {
    public var headline: String
    public var patterns: [String]
    public var cause: String
    public var actions: [String]
    public var alternative: String
    public var commitment: String

    public init(headline: String, patterns: [String], cause: String, actions: [String], alternative: String, commitment: String) {
        self.headline = headline
        self.patterns = patterns
        self.cause = cause
        self.actions = actions
        self.alternative = alternative
        self.commitment = commitment
    }

    public static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "patterns": ["type": "array", "items": ["type": "string"]],
            "cause": ["type": "string"],
            "actions": ["type": "array", "items": ["type": "string"]],
            "alternative": ["type": "string"],
            "commitment": ["type": "string"],
        ],
        "required": ["headline", "patterns", "cause", "actions", "alternative", "commitment"],
        "additionalProperties": false,
    ]
    public static let example = #"{"headline": "一周只在深夜失守", "patterns": ["失守都在 0 点后"], "cause": "你两次说是“累了”", "actions": ["23:50 设闹钟，手机放客厅"], "alternative": "怀旧港片 → 纪录片《龙虎武师》", "commitment": "0 点后不打开 B 站"}"#

    public static func parse(_ text: String) throws -> WeeklyReport {
        var r = try LLMResponse.jsonObject(WeeklyReport.self, from: text)
        let clean = { (xs: [String], n: Int) in Array(xs.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(n)) }
        r.patterns = clean(r.patterns, 3)
        r.actions = clean(r.actions, 2)
        return r
    }

    public var markdown: String {
        var parts = ["**\(headline)**"]
        if !patterns.isEmpty { parts.append("规律：\n" + patterns.map { "- \($0)" }.joined(separator: "\n")) }
        if !cause.isEmpty { parts.append("原因：\(cause)") }
        if !actions.isEmpty { parts.append("行动：\n" + actions.map { "- \($0)" }.joined(separator: "\n")) }
        if !alternative.isEmpty { parts.append("有营养的替代：\(alternative)") }
        parts.append("下周承诺：\(commitment)")
        return parts.joined(separator: "\n\n")
    }

    public var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }
}
