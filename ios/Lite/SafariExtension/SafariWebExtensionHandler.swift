import SafariServices

/// Safari 扩展的原生部分：免费版不和 App 共享数据，计时都在扩展的网页存储里，这里只是回个应答
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
