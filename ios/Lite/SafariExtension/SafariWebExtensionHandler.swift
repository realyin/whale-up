import SafariServices

/// Safari 扩展的原生部分：网页脚本、弹出面板经扩展后台转过来，在这里读写和鲸醒 App 共用的数据（App Group）。
/// 一次 "sync" 带上：Safari 那边还没同步的网页秒数（web：网站 → 秒）、弹出面板里改过的设置（settings）；
/// 回去的是今天的总时长和最新的设置。
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
        if let web = message["web"] as? [String: Any] {
            for (site, value) in web {
                // 一次最多记 10 分钟，防止出错时一下子记一大堆
                let secs = min(600, max(0, (value as? NSNumber)?.doubleValue ?? 0))
                if secs > 0 { u.seconds["Safari · \(site)", default: 0] += secs; changed = true }
            }
        }
        if changed { u.save() }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: u.snapshot]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
