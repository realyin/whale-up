import Foundation

/// 强制关闭对一个网页的判断：关不关、为什么。真正决定关不关的就是它（AppDelegate.enforce），
/// 同一份结果写进记录、给“问问大肥鱼”解释，所以解释和实际行为不会对不上
public enum ForceDecision: Equatable {
    /// 不在强制关闭名单里
    case notListed
    /// 首页、搜索这类“逛”的页面：额度用完也不关，得能去找有营养的
    case browsePage(site: String)
    /// 刚打开、大模型还在判断（最多等 30 秒）
    case awaitingLabel(site: String)
    /// 大模型判为有营养
    case nutritious(site: String, label: ContentLabel)
    /// 没营养，但今天的时间还没用完
    case underLimit(site: String, used: Double, limit: Double)
    /// 没营养、时间用完：关（强制关闭没开时只记不关）
    case overLimit(site: String, used: Double, limit: Double, enabled: Bool)

    /// - rule: 匹配到的强制关闭名单规则；label: 大模型的判断（整站管的网站传 nil）
    public static func make(rule: String?, browsing: Bool, awaitingLabel: Bool, label: ContentLabel?,
                            config: Config, used: Double, limit: Double) -> ForceDecision {
        guard let site = rule else { return .notListed }
        if browsing { return .browsePage(site: site) }
        if awaitingLabel { return .awaitingLabel(site: site) }
        if !JunkJudge.isJunk(siteRuleMatched: true, label: label, config: config), let label {
            return .nutritious(site: site, label: label)
        }
        if used < limit { return .underLimit(site: site, used: used, limit: limit) }
        return .overLimit(site: site, used: used, limit: limit, enabled: config.forceCloseEnabled)
    }

    /// 算不算“在名单网站上看没营养的”（交给 ForceCloser 计算该不该关）
    public var isJunkOnListedSite: Bool {
        switch self {
        case .underLimit, .overLimit: return true
        default: return false
        }
    }

    /// 记录里用的简短代号：同一个网页代号变了才记一条
    public var code: String {
        switch self {
        case .notListed: return "notListed"
        case .browsePage: return "browsePage"
        case .awaitingLabel: return "awaitingLabel"
        case .nutritious: return "nutritious"
        case .underLimit: return "underLimit"
        case .overLimit(_, _, _, let enabled): return enabled ? "close" : "overLimitDisabled"
        }
    }

    public var explanation: String {
        func m(_ s: Double) -> String { "\(Int(s / 60)) 分钟" }
        switch self {
        case .notListed:
            return "不在强制关闭名单里，不会被强制关闭"
        case .browsePage(let site):
            return "\(site) 的首页 / 搜索这类“逛”的页面，额度用完也不关（要能去找有营养的内容）"
        case .awaitingLabel(let site):
            return "\(site) 上刚打开的内容，AI 还在判断有没有营养，最多等 30 秒再决定关不关"
        case .nutritious(let site, let label):
            return "\(site) 上这条 AI 判为有营养（\(label.category)：\(label.reason)），不计时也不关"
        case .underLimit(let site, let used, let limit):
            return "\(site) 上这条算没营养，但今天强制关闭名单网站一共才看了 \(m(used))，上限 \(m(limit))，还没到"
        case .overLimit(let site, let used, let limit, let enabled):
            return enabled
                ? "\(site) 上这条算没营养，今天已经看了 \(m(used))（上限 \(m(limit))），会被强制关闭"
                : "\(site) 上这条算没营养，今天已经看了 \(m(used))（上限 \(m(limit))），但强制关闭模式没开，所以不关"
        }
    }
}
