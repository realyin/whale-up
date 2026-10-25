import Foundation

/// 视频网站上的“逛”的页面：首页、搜索、个人主页、分区……这些页面本身没在放视频，
/// 额度用完以后也不关——不然连找有营养的视频都没法找了。只管真正在放内容的页面。
/// 抖音、快手、TikTok 的首页就是自动播放的视频流，不算“逛”的页面。（Safari 扩展里有一份一样的规则：extract.js 的 isBrowsePage）
public enum PageKind {
    public static func isBrowsePage(_ url: String) -> Bool {
        guard let u = URLComponents(string: url), let host = u.host?.lowercased() else { return false }
        let path = u.path.isEmpty ? "/" : u.path.lowercased()
        let on = { (domain: String) in host == domain || host.hasSuffix("." + domain) }
        let starts = { (prefixes: [String]) in prefixes.contains { path.hasPrefix($0) } }

        if on("bilibili.com") {
            if host.hasPrefix("search.") || host.hasPrefix("space.") || host.hasPrefix("t.") { return true }
            if starts(["/video/", "/bangumi/", "/cheese/", "/list/", "/festival/"]) { return false }
            return path == "/" || starts(["/v/", "/c/", "/search", "/channel", "/anime", "/movie", "/guochuang", "/tv"])
        }
        if on("youtube.com") {
            if starts(["/watch", "/shorts", "/live/"]) { return false }
            return path == "/" || starts(["/results", "/feed/", "/@", "/channel/", "/c/", "/user/", "/playlist"])
        }
        if on("douyin.com") || on("kuaishou.com") || on("tiktok.com") {
            return starts(["/search", "/user/", "/profile", "/@"])
        }
        if on("x.com") || on("twitter.com") {
            // 只有点开的单条推文（/用户/status/编号）算内容，时间线、搜索、通知、个人主页都是逛
            return path.range(of: #"^/[^/]+/status/\d+"#, options: .regularExpression) == nil
        }
        if on("xiaohongshu.com") {
            // /explore 是卡片墙（不自动放），/explore/<id> 才是一条笔记
            return path == "/" || path == "/explore" || path == "/explore/" || starts(["/search_result", "/user/profile"])
        }
        return false
    }
}
