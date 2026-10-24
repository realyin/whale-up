import SafariServices

/// Safari 扩展的原生部分：网页脚本、弹出面板经扩展后台转过来，在这里读写和鲸醒 App 共用的数据（App Group）。
/// 一次 "sync" 带上：Safari 里今天每个网站一共刷了多少秒（web：网站 → 秒，总数）、弹出面板里改过的设置（settings）；
/// 回去的是 App 自己记的时间（appUsed）和最新的设置。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        if message["type"] as? String == "judge" { return judge(message, context) }
        var u = Usage.load()
        var changed = false

        if let settings = message["settings"] as? [String: Any] {
            if let limit = (settings["limit"] as? NSNumber)?.intValue { u.setLimit(limit) }
            // 扩展那边已经输过随机码、数过次数了，这里直接记下
            if let extra = (settings["extra"] as? NSNumber)?.intValue { u.extra = min(180, max(5 - u.limit, extra)) }
            if let grants = (settings["grants"] as? NSNumber)?.intValue { u.grants = max(u.grants, grants) }
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
            // 有营养的时间：记下来给你看，不算进每天的时长
            for (site, value) in message["good"] as? [String: Any] ?? [:] {
                let secs = min(24 * 3600, max(0, (value as? NSNumber)?.doubleValue ?? 0))
                if secs > (u.good[site] ?? 0) { u.good[site] = secs; changed = true }
            }
        }
        if changed { u.save() }

        reply(u.snapshot, context)
    }

    /// 问 DeepSeek 这个视频 / 网页有没有营养；判断过的直接用记下的结果
    private func judge(_ message: [String: Any], _ context: NSExtensionContext) {
        let key = message["key"] as? String ?? ""
        if let v = Judge.cached(key) { return reply(v.dict, context) }
        let settings = AISettings.load()
        guard settings.ready else { return reply(["off": true], context) }
        var info: [String: String] = [:]
        for k in ["site", "title", "author", "tags", "description"] { info[k] = message[k] as? String ?? "" }
        Task {
            do {
                let v = try await Judge.ask(info, settings: settings)
                Judge.remember(key, v)
                reply(v.dict, context)
            } catch {
                reply(["error": "\(error)"], context)
            }
        }
    }

    private func reply(_ body: [String: Any], _ context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: body]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
