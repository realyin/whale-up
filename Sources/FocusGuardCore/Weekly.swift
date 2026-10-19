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
            你是用户自己请来的注意力教练。下面是用户一周里在电脑上看视频、刷网页的记录汇总，以及每天的小结。
            请写一份每周复盘，帮他看清自己的模式，并给出真正可执行的改变。语气像了解他、说话直接的朋友，不说教，用记录里的具体内容说话。

            用 Markdown，按下面的小标题写，总共不超过 800 字：
            ## 本周概况
            ## 模式
            哪些时间段、哪些情绪或场景最容易刷；和有营养内容的时间对比；本周比上周的趋势（如果看得出来）。
            ## 背后的原因
            结合他自己说的原因和内容的“钩子”（猎奇、搞笑、焦虑……），推断他真正在满足什么需求（休息、逃避压力、社交、刺激……）。
            ## 需要加强什么
            针对原因给出两三条具体建议，不要泛泛的“少刷点”。
            ## 有营养的替代
            根据他爱看的主题，推荐对应的有营养内容方向（比如爱看历史八卦 → 好读的历史书或纪录片）。
            ## 下周的一个承诺
            一个具体、可检查的小目标。

            记录很少时就简短地写，不要编造。
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
