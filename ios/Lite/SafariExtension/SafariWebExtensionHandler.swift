import SafariServices

/// Safari 扩展的原生部分：网页脚本、弹出面板经扩展后台转过来，在这里读写和鲸醒 App 共用的数据（App Group）。
/// 一次 "sync" 带上：Safari 里今天每个网站一共刷了多少秒（web：网站 → 秒，总数）、弹出面板里改过的设置（settings）；
/// 回去的是 App 自己记的时间（appUsed）和最新的设置。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        var u = Usage.load()
        var changed = false

        if let settings = message["settings"] as? [String: Any] {
            if let limit = (settings["limit"] as? NSNumber)?.intValue { u.setLimit(limit) }
            if let extra = (settings["extra"] as? NSNumber)?.intValue { u.extra = 0; u.adjust(extra) }
            if let sites = settings["sites"] as? [String], !sites.isEmpty { u.sites = sites }
            changed = true
        }
        // Safari 里每个网站今天一共刷了多少秒（总数，不是增量）：直接记下，取大的那个，发几次都一样。
        // 扩展那边的“今天”和这边不是同一天时（刚过凌晨 4 点）不收
        if let web = message["web"] as? [String: Any], (message["day"] as? String).map({ $0 == u.dayKey() }) ?? true {
            for (site, value) in web {
                let secs = min(24 * 3600, max(0, (value as? NSNumber)?.doubleValue ?? 0))
                let key = Usage.safariPrefix + site
                if secs > (u.seconds[key] ?? 0) { u.seconds[key] = secs; changed = true }
            }
        }
        if changed { u.save() }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: u.snapshot]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
