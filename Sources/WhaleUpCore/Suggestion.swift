import Foundation

/// 报告里给出的、可以一键生效的设置建议
public struct Suggestion: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case none, dailyBudget, nightLimit, forceCloseSite, pauseBeforeJunk, workHours
    }

    public var kind: Kind
    /// forceCloseSite 用
    public var site: String
    /// dailyBudget / nightLimit / workHours 用
    public var minutes: Int

    public init(kind: Kind, site: String, minutes: Int) {
        self.kind = kind
        self.site = site
        self.minutes = minutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .none
        site = (try? c.decode(String.self, forKey: .site)) ?? ""
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 0
    }

    private var siteRule: String? { Classifier.siteRule(from: site) }

    /// 按钮上的文字；没有意义或已经是当前设置时返回 nil（不显示按钮）
    public func title(for config: Config) -> String? {
        switch kind {
        case .none:
            return nil
        case .dailyBudget:
            guard minutes > 0, Double(minutes) != config.dailyBudgetMinutes else { return nil }
            return "每日额度设为 \(minutes) 分钟"
        case .nightLimit:
            guard minutes > 0, Double(minutes) != config.nightLimitMinutes else { return nil }
            return "夜间连续 \(minutes) 分钟就提醒"
        case .forceCloseSite:
            guard let rule = siteRule, !(config.forceCloseEnabled && config.forceCloseSites.contains(rule)) else { return nil }
            return "强制关闭 \(rule)"
        case .pauseBeforeJunk:
            return config.pauseBeforeJunk ? nil : "开启“打开前先停一下”"
        case .workHours:
            guard minutes > 0, !(config.workHoursEnabled && Double(minutes) == config.workLimitMinutes) else { return nil }
            return "工作时段连续 \(minutes) 分钟就提醒"
        }
    }

    public func apply(to config: inout Config) {
        switch kind {
        case .none:
            break
        case .dailyBudget:
            config.dailyBudgetMinutes = Double(minutes)
        case .nightLimit:
            config.nightLimitMinutes = Double(minutes)
        case .forceCloseSite:
            guard let rule = siteRule else { return }
            config.forceCloseEnabled = true
            if !config.forceCloseSites.contains(rule) { config.forceCloseSites.append(rule) }
        case .pauseBeforeJunk:
            config.pauseBeforeJunk = true
        case .workHours:
            config.workHoursEnabled = true
            config.workLimitMinutes = Double(minutes)
        }
    }

    public static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": Kind.allCases.map(\.rawValue)],
            "site": ["type": "string"],
            "minutes": ["type": "integer"],
        ],
        "required": ["kind", "site", "minutes"],
        "additionalProperties": false,
    ]

    /// 告诉大模型：这是电脑上的助手，有哪些功能、用户现在怎么设置的，以及 setting 怎么填
    public static func guide(for c: Config) -> String {
        let budget = c.dailyBudgetMinutes > 0
            ? "\(Int(c.dailyBudgetMinutes)) 分钟（用完后\(c.budgetCloses ? "直接关网页" : "提醒")）" : "未设置"
        let force = c.forceCloseEnabled
            ? "开启，每天累计 \(Int(c.forceCloseMinutes)) 分钟后关闭、当天再打开也关，网站：\(c.forceCloseSites.joined(separator: "、"))" : "关闭"
        let work = c.workHoursEnabled
            ? "\(c.workStartHour):00–\(c.workEndHour):00 连续 \(Int(c.workLimitMinutes)) 分钟就提醒" : "未开启"
        return """
            场景：你是 Mac 电脑上的“鲸醒”助手，只能看到并管理电脑浏览器里的网页和电脑上的 App，管不到手机。所有建议都必须是在电脑前能做到的，不要提手机。
            这个助手已有的功能和用户当前的设置：
            - 每日额度：\(budget)
            - 连续刷多久提醒：白天 \(Int(c.daytimeLimitMinutes)) 分钟，夜间（\(c.nightStartHour):00–\(c.nightEndHour):00）\(Int(c.nightLimitMinutes)) 分钟
            - 强制关闭：\(force)
            - 打开前先停一下：\(c.pauseBeforeJunk ? "开启" : "关闭")
            - 工作时段：\(work)
            如果行动能用上面的功能做到，在 setting 里给出，用户可以一键设置：kind 可选 dailyBudget（每日额度，minutes 填分钟数）、nightLimit（夜间连续几分钟提醒）、forceCloseSite（把 site 填的网站加入强制关闭）、pauseBeforeJunk（开启打开前先停一下）、workHours（开启工作时段，minutes 填连续几分钟提醒）。不要建议已经是当前设置的内容；用不上就把 kind 填 none、site 填空字符串、minutes 填 0。
            """
    }
}
