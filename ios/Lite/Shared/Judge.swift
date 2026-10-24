import Foundation

/// AI 判断的设置：存在 App Group 里，鲸醒 App 里填，Safari 扩展的原生部分读
struct AISettings: Codable, Equatable {
    var enabled = false
    var apiKey = ""
    var model = "deepseek-flash"
    /// 和 Mac 版同一套默认标准
    var preferences = "学习、技术、编程、英语、知识科普、纪录片、新闻深度分析算有营养；娱乐八卦、搞笑段子、情感纠纷、无脑短剧、游戏直播切片、猎奇和吵架类内容算没营养。"

    private static let key = "aiSettings"

    static func load() -> AISettings {
        // 开发用：用 -aiOn 启动时直接打开，截图看界面
        if ProcessInfo.processInfo.arguments.contains("-aiOn") { var s = AISettings(); s.enabled = true; return s }
        guard let data = Usage.defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Usage.defaults.set(data, forKey: Self.key) }
    }

    var ready: Bool { enabled && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// 大模型对一个视频 / 网页的判断
struct Verdict: Codable, Equatable {
    var isJunk: Bool
    var category: String
    var reason: String
    var at: Double

    var dict: [String: Any] { ["isJunk": isJunk, "category": category, "reason": reason] }
}

/// 用 DeepSeek 判断“有没有营养”；同一个内容判断过就记住（最多记 500 条、7 天）
enum Judge {
    private static let cacheKey = "verdicts"

    static func cached(_ key: String) -> Verdict? {
        let all = loadCache()
        guard let v = all[key], Date().timeIntervalSince1970 - v.at < 7 * 86400 else { return nil }
        return v
    }

    static func remember(_ key: String, _ v: Verdict) {
        var all = loadCache()
        all[key] = v
        if all.count > 500 {
            for (k, _) in all.sorted(by: { $0.value.at < $1.value.at }).prefix(all.count - 500) { all.removeValue(forKey: k) }
        }
        if let data = try? JSONEncoder().encode(all) { Usage.defaults.set(data, forKey: cacheKey) }
    }

    private static func loadCache() -> [String: Verdict] {
        Usage.defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([String: Verdict].self, from: $0) } ?? [:]
    }

    /// 和 Mac 版同一套提示词：只发网站、标题、作者、标签、简介，不发完整网址
    static func prompt(_ info: [String: String], preferences: String) -> (system: String, user: String) {
        let system = """
            你是一个帮助用户管理注意力的助手。用户在手机上看了一个视频或网页，请判断这条内容对用户来说是“有营养”还是“没营养”。

            有营养：能让人学到东西、获得有用信息、深入思考，或对工作学习有帮助。
            没营养：主要提供即时娱乐和刺激，看完没有实际收获，容易让人停不下来。

            用户自己的标准（优先遵守）：
            \(preferences)

            只根据给出的信息判断；信息很少时按最可能的情况判断。isJunk 为 true 表示没营养。
            category 用两到四个字的中文主题，例如：学习、技术、新闻、知识科普、娱乐、搞笑、情感、游戏、音乐、影视、生活。
            reason 用一句中文说明理由，不超过 30 个字。

            请只输出一个 JSON 对象，格式示例：
            {"isJunk": true, "category": "娱乐", "reason": "搞笑段子，看完没有收获"}
            """
        var lines = ["网站：\(info["site"] ?? "")", "标题：\(info["title"] ?? "")"]
        if let a = info["author"], !a.isEmpty { lines.append("作者：\(a)") }
        if let t = info["tags"], !t.isEmpty { lines.append("标签：\(t)") }
        if let d = info["description"], !d.isEmpty { lines.append("简介：\(d)") }
        return (system, lines.joined(separator: "\n"))
    }

    enum Failure: Error, CustomStringConvertible {
        case off, http(String), badOutput(String)
        var description: String {
            switch self {
            case .off: return "还没开 AI 判断或没填 API Key"
            case .http(let m): return "DeepSeek 返回错误：\(m)"
            case .badOutput(let m): return "看不懂 DeepSeek 的回答：\(m)"
            }
        }
    }

    static func ask(_ info: [String: String], settings: AISettings = .load()) async throws -> Verdict {
        guard settings.ready else { throw Failure.off }
        let p = prompt(info, preferences: settings.preferences)
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        req.timeoutInterval = 20
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.model,
            "max_tokens": 300,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": p.system], ["role": "user", "content": p.user]],
        ] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let error = json["error"] as? [String: Any] ?? [:]
            let message = error["message"] as? String ?? raw
            throw Failure.http(String(message.prefix(120)))
        }
        let choices = json["choices"] as? [[String: Any]] ?? []
        let reply = choices.first?["message"] as? [String: Any] ?? [:]
        let content = reply["content"] as? String ?? ""
        let obj = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [String: Any] ?? [:]
        guard let isJunk = obj["isJunk"] as? Bool else { throw Failure.badOutput(String(raw.prefix(120))) }
        return Verdict(isJunk: isJunk, category: obj["category"] as? String ?? "", reason: obj["reason"] as? String ?? "",
                       at: Date().timeIntervalSince1970)
    }
}
