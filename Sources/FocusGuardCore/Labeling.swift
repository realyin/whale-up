import Foundation

/// 大模型对一条内容的判断
public struct ContentLabel: Codable, Equatable {
    public var isJunk: Bool
    /// 营养分 1（纯消遣）– 5（很有收获）
    public var nutrition: Int
    /// 主题，如 学习 / 娱乐 / 新闻 / 情感
    public var category: String
    /// 一句话理由
    public var reason: String
    public var model: String
    public var labeledAt: Double

    public init(isJunk: Bool, nutrition: Int, category: String, reason: String, model: String,
                labeledAt: Double = Date().timeIntervalSince1970) {
        self.isJunk = isJunk
        self.nutrition = min(5, max(1, nutrition))
        self.category = category
        self.reason = reason
        self.model = model
        self.labeledAt = labeledAt
    }
}

/// 结合网站规则和大模型判断，决定当前内容算不算“没营养”
public enum JunkJudge {
    public static func isJunk(siteRuleMatched: Bool, label: ContentLabel?, config: Config) -> Bool {
        guard config.llm.enabled, let label else { return siteRuleMatched }
        return label.isJunk
    }
}

public enum LabelPrompt {
    /// 只发送判断所需的信息：网站、标题、作者、标签、简介。不发完整网址，不发观看时间。
    public static func make(for v: ContentView, llm: LLMConfig) -> (system: String, user: String) {
        let system = """
            你是一个帮助用户管理注意力的助手。用户在电脑上看了一个视频或网页，请判断这条内容对用户来说是“有营养”还是“没营养”。

            有营养：能让人学到东西、获得有用信息、深入思考，或对工作学习有帮助。
            没营养：主要提供即时娱乐和刺激，看完没有实际收获，容易让人停不下来。

            用户自己的标准（优先遵守）：
            \(llm.preferences)

            只根据给出的信息判断；信息很少时按最可能的情况判断。
            nutrition 是 1 到 5 的整数：1 纯消遣，3 一般，5 很有收获。isJunk 为 true 表示没营养。
            category 用两到四个字的中文主题，例如：学习、技术、新闻、知识科普、娱乐、搞笑、情感、游戏、音乐、影视、生活。
            reason 用一句中文说明理由，不超过 30 个字。
            """
        var lines = ["网站：\(v.site)", "类型：\(v.kind == "video" ? "视频" : "网页")", "标题：\(v.title)"]
        if let author = v.author, !author.isEmpty { lines.append("作者：\(author)") }
        if !v.tags.isEmpty { lines.append("标签：\(v.tags.joined(separator: "、"))") }
        if let desc = v.description, !desc.isEmpty, desc != "-" { lines.append("简介：\(desc)") }
        if let d = v.mediaDuration, d > 0 { lines.append("视频时长：\(Int(d / 60)) 分 \(Int(d) % 60) 秒") }
        return (system, lines.joined(separator: "\n"))
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "isJunk": ["type": "boolean"],
            "nutrition": ["type": "integer"],
            "category": ["type": "string"],
            "reason": ["type": "string"],
        ],
        "required": ["isJunk", "nutrition", "category", "reason"],
        "additionalProperties": false,
    ]
}

public enum LLMError: Error, CustomStringConvertible {
    case missingAPIKey
    case badBaseURL(String)
    case api(String)
    case refused
    case truncated
    case badOutput(String)

    public var description: String {
        switch self {
        case .missingAPIKey: return "还没有填 API Key"
        case .badBaseURL(let u): return "接口地址不正确：\(u)"
        case .api(let m): return "接口返回错误：\(m)"
        case .refused: return "模型拒绝回答这条内容"
        case .truncated: return "模型输出被截断"
        case .badOutput(let m): return "模型输出无法解析：\(m)"
        }
    }
}

public enum LLMRequest {
    public static func labeling(_ v: ContentView, llm: LLMConfig, apiKey: String?) throws -> URLRequest {
        let prompt = LabelPrompt.make(for: v, llm: llm)
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if llm.provider != .ollama && key.isEmpty { throw LLMError.missingAPIKey }

        let body: [String: Any]
        var req: URLRequest
        switch llm.provider {
        case .anthropic:
            req = URLRequest(url: try endpoint(llm.baseURL, default: "https://api.anthropic.com", path: "v1/messages"))
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": llm.taggingModel,
                "max_tokens": 2048,
                "system": prompt.system,
                "messages": [["role": "user", "content": prompt.user]],
                // 分类任务简单，低思考强度即可；格式由 JSON Schema 约束
                "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": LabelPrompt.schema]],
            ]
        case .openai, .ollama:
            let base = llm.provider == .ollama ? "http://127.0.0.1:11434/v1" : "https://api.openai.com/v1"
            req = URLRequest(url: try endpoint(llm.baseURL, default: base, path: "chat/completions"))
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = [
                "model": llm.taggingModel,
                "messages": [["role": "system", "content": prompt.system], ["role": "user", "content": prompt.user]],
                "response_format": ["type": "json_schema",
                                    "json_schema": ["name": "content_label", "strict": true, "schema": LabelPrompt.schema]],
            ]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func endpoint(_ custom: String, default def: String, path: String) throws -> URL {
        var base = custom.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = def }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/" + path), url.scheme?.hasPrefix("http") == true else {
            throw LLMError.badBaseURL(custom)
        }
        return url
    }
}

public enum LLMResponse {
    public static func parseLabel(_ data: Data, provider: LLMProvider, model: String) throws -> ContentLabel {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badOutput(String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        if let error = json["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? "\(error)"
            throw LLMError.api(message)
        }

        let text: String
        switch provider {
        case .anthropic:
            switch json["stop_reason"] as? String {
            case "refusal": throw LLMError.refused
            case "max_tokens": throw LLMError.truncated
            default: break
            }
            let blocks = json["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .openai, .ollama:
            let choice = (json["choices"] as? [[String: Any]])?.first
            text = (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        }

        struct Raw: Decodable {
            var isJunk: Bool
            var nutrition: Int
            var category: String
            var reason: String
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(text.utf8)) else {
            throw LLMError.badOutput(String(text.prefix(200)))
        }
        return ContentLabel(isJunk: raw.isJunk, nutrition: raw.nutrition, category: raw.category,
                            reason: raw.reason, model: model)
    }
}
