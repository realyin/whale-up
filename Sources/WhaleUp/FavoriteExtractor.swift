import Foundation
import WhaleUpCore

/// 扩展上报的收藏内容
struct FavoriteInput: Decodable {
    var url: String
    var title: String?
    var author: String?
    var text: String?
    var textKind: String?
}

/// 收藏后排队请大模型提炼要点（用“写报告用的模型”，量少、要质量）
@MainActor
final class FavoriteExtractor {
    private let store: ContentStore
    private var running = false
    var onChange: (_ finished: Favorite?) -> Void = { _ in }

    init(store: ContentStore) {
        self.store = store
    }

    /// 保存收藏并开始提炼。不能收藏时返回原因（敏感网站、网站首页）
    @discardableResult
    func save(_ f: Favorite, config: Config) -> String? {
        if config.isSensitive(url: f.url) { return "这个网站在“永不记录”名单里，不能收藏" }
        if let reason = f.rejectionReason { return reason }
        guard (try? store.saveFavorite(f)) != nil else { return "保存失败" }
        onChange(nil)
        kick(config: config)
        return nil
    }

    /// 从看过的内容收藏：App 自己抓网页正文，抓不到就用记录里的简介和标签
    @discardableResult
    func saveFromHistory(_ v: ContentView, config: Config) async -> String? {
        if let reason = Favorite(url: v.url, title: v.title, text: "", textKind: .none).rejectionReason { return reason }
        var text = ""
        var kind = Favorite.TextKind.none
        if v.kind != "video", let url = URL(string: v.url) {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let page = HTMLText.extract(html)
                if page.text.count >= 200 { text = String(page.text.prefix(20000)); kind = .article }
            }
        }
        if text.isEmpty {
            let desc = [v.description ?? "", v.tags.isEmpty ? "" : "标签：" + v.tags.joined(separator: "、")]
                .filter { !$0.isEmpty && $0 != "-" }.joined(separator: "\n")
            text = desc
            kind = desc.isEmpty ? .none : .description
        }
        return save(Favorite(url: v.url, title: v.title, author: v.author, text: text, textKind: kind), config: config)
    }

    func retry(_ f: Favorite, config: Config) {
        try? store.resetFavorite(id: f.id)
        onChange(nil)
        kick(config: config)
    }

    func kick(config: Config) {
        guard !running else { return }
        running = true
        Task {
            await drain(config: config)
            running = false
        }
    }

    private func drain(config: Config) async {
        var tried = Set<Int64>()
        while let next = (try? store.favorites())?.first(where: { $0.status == .pending && !tried.contains($0.id) }) {
            tried.insert(next.id)
            guard config.llm.enabled else {
                try? store.setFavoriteResult(id: next.id, points: nil, error: "需要先在设置里开启 AI 判断")
                onChange(nil)
                continue
            }
            do {
                let p = KeyPointsPrompt.make(for: next)
                let llm = config.llm
                let spec = ChatSpec(system: p.system, user: p.user, model: llm.reportModel, maxTokens: 4000, effort: "medium",
                                    jsonSchema: KeyPoints.schema, jsonExample: KeyPoints.example)
                let request = try LLMRequest.chat(spec, llm: llm, apiKey: APIKeyStore.get(llm.provider), timeout: 120)
                let (data, _) = try await URLSession.shared.data(for: request)
                let points = try KeyPoints.parse(try LLMResponse.text(data, provider: llm.provider))
                try? store.setFavoriteResult(id: next.id, points: points, error: nil)
                var done = next
                done.points = points
                done.status = .done
                onChange(done)
            } catch {
                try? store.setFavoriteResult(id: next.id, points: nil, error: "\(error)")
                onChange(nil)
            }
        }
    }
}
