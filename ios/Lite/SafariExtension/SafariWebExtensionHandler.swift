import SafariServices

/// Safari 扩展的原生部分：网页里的脚本经扩展后台转过来，在这里读写和鲸醒 App 共用的数据（App Group）
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        var u = Usage.load()
        switch message["type"] as? String {
        case "tick":
            // 网页在前台时每 5 秒记一次；今天已经刷够了就不再记
            let secs = min(30, message["seconds"] as? Double ?? 0)
            let site = message["site"] as? String ?? "网页"
            if !u.isOver { u.seconds["Safari · \(site)", default: 0] += secs }
        case "adjust":
            u.adjust(message["minutes"] as? Int ?? 0)
        case "reset":
            u.extra = 0
        case "setLimit":
            u.setLimit(message["limit"] as? Int ?? u.limit)
        case "setSites":
            if let sites = message["sites"] as? [String] { u.sites = sites }
        default:
            break  // "get"：只读
        }
        if (message["type"] as? String ?? "get") != "get" { u.save() }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: u.snapshot]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
