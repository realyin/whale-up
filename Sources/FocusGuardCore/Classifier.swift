import Foundation

/// 某一时刻前台正在做的事
public struct Activity: Equatable {
    public var appName: String
    public var bundleID: String?
    /// 前台是浏览器时，当前标签页的网址和标题
    public var url: String?
    public var title: String?

    public init(appName: String, bundleID: String?, url: String? = nil, title: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.url = url
        self.title = title
    }
}

public enum Classifier {
    /// 如果当前活动属于“没营养”内容，返回命中的规则；否则返回 nil。
    public static func junkReason(for activity: Activity, config: Config) -> String? {
        let name = activity.appName.lowercased()
        for rule in config.junkApps where !rule.isEmpty {
            if name.contains(rule.lowercased()) || activity.bundleID == rule { return rule }
        }
        return activity.url.flatMap { junkSite(for: $0, config: config) }
    }

    /// 网址命中的“没营养”网站规则；不命中返回 nil。
    public static func junkSite(for urlString: String, config: Config) -> String? {
        matchSite(urlString, rules: config.junkSites)
    }

    /// 网址命中的网站规则（规则写法同 junkSites）；不命中返回 nil。
    public static func matchSite(_ urlString: String, rules: [String]) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        return rules.first { siteMatches($0, host: host, path: url.path) }
    }

    /// "youtube.com/shorts" 匹配 www.youtube.com 下 /shorts 开头的路径；
    /// "x.com" 匹配 x.com 和 *.x.com，但不匹配 box.com。
    static func siteMatches(_ rule: String, host: String, path: String) -> Bool {
        let parts = rule.lowercased().split(separator: "/", maxSplits: 1)
        guard let ruleHost = parts.first.map(String.init), !ruleHost.isEmpty else { return false }
        guard host == ruleHost || host.hasSuffix("." + ruleHost) else { return false }
        if parts.count == 2 { return path.lowercased().hasPrefix("/" + parts[1]) }
        return true
    }
}
