import Foundation
import Security
import WhaleUpCore

/// API Key 存在系统钥匙串，按服务商分开
enum APIKeyStore {
    private static let service = "io.github.realyin.whaleup.llm"
    /// 改名前（FocusGuard）存 Key 用的服务名，读不到新的时从这里搬过来
    private static let oldService = "\(Migration.oldBundleID).llm"

    static func get(_ provider: LLMProvider) -> String? {
        if let key = read(provider, service: service) { return key }
        guard let old = read(provider, service: oldService) else { return nil }
        set(old, for: provider)
        return old
    }

    private static func read(_ provider: LLMProvider, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, for provider: LLMProvider) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// 在后台逐条请大模型判断“有没有营养”，结果写回内容库。同一条内容判断过就复用。
@MainActor
final class Labeler {
    private let store: ContentStore
    private var running = false
    private(set) var lastError: String?
    private(set) var lastSuccessAt: Date?
    var onChange: () -> Void = {}

    init(store: ContentStore) {
        self.store = store
    }

    /// 有新内容时调用；已在运行就跳过，运行中的循环会接着处理新来的
    func kick(config: Config) {
        guard config.llm.enabled, !running else { return }
        running = true
        Task {
            await drain(llm: config.llm)
            running = false
        }
    }

    private func drain(llm: LLMConfig) async {
        var handled = Set<String>()
        while let batch = try? store.unlabeledViews(limit: 5).filter({ !handled.contains($0.viewId) }), !batch.isEmpty {
            for view in batch {
                handled.insert(view.viewId)
                if let cached = try? store.cachedLabel(for: view) {
                    try? store.setLabel(viewId: view.viewId, label: cached)
                    onChange()
                    continue
                }
                do {
                    let label = try await Self.classify(view, llm: llm)
                    try? store.setLabel(viewId: view.viewId, label: label)
                    lastError = nil
                    lastSuccessAt = Date()
                    onChange()
                } catch LLMError.missingAPIKey {
                    lastError = LLMError.missingAPIKey.description
                    try? store.addEvent(AppEvent(kind: .error, detail: "AI 判断用不了：\(LLMError.missingAPIKey.description)"))
                    onChange()
                    return  // 没有 Key，后面的也不用试了
                } catch {
                    lastError = "\(error)"
                    try? store.addEvent(AppEvent(kind: .error, site: view.site, url: view.url, title: view.title,
                                                 detail: "AI 判断有没有营养失败：\(error)"))
                    try? store.markLabelAttempt(viewId: view.viewId)
                    onChange()
                }
            }
        }
    }

    /// 设置页“测试”用的两条示例：一条学习、一条娱乐
    static let samples = [
        ContentView(viewId: "t1", url: "https://www.bilibili.com/video/test1", title: "坚持这样练英语听力，1个月就能看见效果",
                    author: "英语老师Lee", tags: ["英语听力", "英语学习"], kind: "video", startedAt: 0, endedAt: 0, activeSeconds: 0),
        ContentView(viewId: "t2", url: "https://www.douyin.com/video/test2", title: "这也太好笑了吧哈哈哈 #搞笑 #沙雕日常",
                    author: "快乐小王", tags: ["搞笑", "沙雕日常"], kind: "video", startedAt: 0, endedAt: 0, activeSeconds: 0),
    ]

    static func classify(_ view: ContentView, llm: LLMConfig) async throws -> ContentLabel {
        let request = try LLMRequest.labeling(view, llm: llm, apiKey: APIKeyStore.get(llm.provider))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try LLMResponse.parseLabel(data, provider: llm.provider, model: llm.taggingModel)
    }
}
