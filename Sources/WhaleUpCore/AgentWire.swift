import Foundation

/// “问问大肥鱼”的对话：大模型可以调用工具（查记录、查判断、改名单……），多轮来回直到给出回答。
/// 这里只管消息格式和上下文长度，工具本身在 App 里实现

public struct AgentToolCall: Codable, Equatable {
    public var id: String
    public var name: String
    /// JSON 字符串
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public enum AgentMessage: Codable, Equatable {
    case user(String)
    /// reasoning：DeepSeek 思考模式的推理内容，同一轮里调用工具时要原样传回
    case assistant(text: String, reasoning: String?, calls: [AgentToolCall])
    case tool(id: String, name: String, result: String)

    var isUser: Bool { if case .user = self { return true } else { return false } }

    var size: Int {
        switch self {
        case .user(let t): return t.count
        case .assistant(let t, let r, let calls): return t.count + (r?.count ?? 0) + calls.reduce(0) { $0 + $1.arguments.count + 40 }
        case .tool(_, _, let r): return r.count + 40
        }
    }
}

public struct AgentTool {
    public var name: String
    public var description: String
    /// JSON Schema（type: object）
    public var parameters: [String: Any]

    public init(name: String, description: String, parameters: [String: Any] = ["type": "object", "properties": [:]]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct AgentReply: Equatable {
    public var text: String
    public var reasoning: String?
    public var calls: [AgentToolCall]
}

public enum AgentWire {
    public static func request(system: String, messages: [AgentMessage], tools: [AgentTool], llm: LLMConfig,
                               apiKey: String?, model: String, timeout: TimeInterval = 90) throws -> URLRequest {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if llm.provider != .ollama && key.isEmpty { throw LLMError.missingAPIKey }
        var req: URLRequest
        var body: [String: Any]
        switch llm.provider {
        case .anthropic:
            req = URLRequest(url: try LLMRequest.endpoint(llm.baseURL, default: "https://api.anthropic.com", path: "v1/messages"))
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 4096, "system": system, "messages": anthropicMessages(messages)]
            if !tools.isEmpty {
                body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
            }
        case .openai, .deepseek, .ollama:
            let base = llm.provider == .ollama ? "http://127.0.0.1:11434/v1"
                : llm.provider == .deepseek ? "https://api.deepseek.com" : "https://api.openai.com/v1"
            req = URLRequest(url: try LLMRequest.endpoint(llm.baseURL, default: base, path: "chat/completions"))
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model, "messages": [["role": "system", "content": system]]
                    + openAIMessages(messages, withReasoning: llm.provider == .deepseek)]
            if llm.provider == .deepseek { body["max_tokens"] = 8000 }
            if !tools.isEmpty {
                body["tools"] = tools.map {
                    ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]]
                }
            }
        }
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func openAIMessages(_ messages: [AgentMessage], withReasoning: Bool) -> [[String: Any]] {
        // 推理内容只传回最后一次用户提问之后的（这一轮里还在调用工具）；更早的轮次不用
        let lastUser = messages.lastIndex(where: \.isUser) ?? 0
        return messages.enumerated().map { i, m in
            switch m {
            case .user(let text):
                return ["role": "user", "content": text]
            case .assistant(let text, let reasoning, let calls):
                var o: [String: Any] = ["role": "assistant", "content": text]
                if !calls.isEmpty {
                    o["tool_calls"] = calls.map {
                        ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
                    }
                }
                if withReasoning, i > lastUser, let reasoning, !reasoning.isEmpty { o["reasoning_content"] = reasoning }
                return o
            case .tool(let id, _, let result):
                return ["role": "tool", "tool_call_id": id, "content": result]
            }
        }
    }

    static func anthropicMessages(_ messages: [AgentMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for m in messages {
            switch m {
            case .user(let text):
                out.append(["role": "user", "content": text])
            case .assistant(let text, _, let calls):
                var blocks: [[String: Any]] = []
                if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
                for c in calls {
                    let input = (try? JSONSerialization.jsonObject(with: Data(c.arguments.utf8))) as? [String: Any] ?? [:]
                    blocks.append(["type": "tool_use", "id": c.id, "name": c.name, "input": input])
                }
                out.append(["role": "assistant", "content": blocks])
            case .tool(let id, _, let result):
                // 连着的几个工具结果要放进同一条 user 消息
                let block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": result]
                if var last = out.last, last["role"] as? String == "user", var blocks = last["content"] as? [[String: Any]],
                   blocks.first?["type"] as? String == "tool_result" {
                    blocks.append(block)
                    last["content"] = blocks
                    out[out.count - 1] = last
                } else {
                    out.append(["role": "user", "content": [block]])
                }
            }
        }
        return out
    }

    public static func parse(_ data: Data, provider: LLMProvider) throws -> AgentReply {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badOutput(String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        if let error = json["error"] {
            throw LLMError.api((error as? [String: Any])?["message"] as? String ?? "\(error)")
        }
        switch provider {
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" { throw LLMError.refused }
            let blocks = json["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            let calls = blocks.filter { $0["type"] as? String == "tool_use" }.map { b -> AgentToolCall in
                let input = b["input"] ?? [String: Any]()
                let args = (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return AgentToolCall(id: b["id"] as? String ?? UUID().uuidString, name: b["name"] as? String ?? "", arguments: args)
            }
            return AgentReply(text: text, reasoning: nil, calls: calls)
        case .openai, .deepseek, .ollama:
            let message = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]) ?? [:]
            let calls = (message["tool_calls"] as? [[String: Any]] ?? []).map { c -> AgentToolCall in
                let f = c["function"] as? [String: Any] ?? [:]
                return AgentToolCall(id: c["id"] as? String ?? UUID().uuidString, name: f["name"] as? String ?? "",
                                     arguments: f["arguments"] as? String ?? "{}")
            }
            return AgentReply(text: message["content"] as? String ?? "", reasoning: message["reasoning_content"] as? String,
                              calls: calls)
        }
    }
}

/// 上下文管理：对话越聊越长，发给大模型前先压一压
public enum AgentMemory {
    /// 单个工具结果最长多少字（再长的截掉，提示大模型缩小范围再查）
    public static let maxToolResult = 6000
    /// 以前轮次的工具结果压到多少字（结论已经在当时的回答里了）
    public static let oldToolResult = 400

    public static func clip(_ text: String, _ limit: Int = maxToolResult) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n……（太长，后面省略了。需要的话缩小范围再查）"
    }

    /// 1. 最后一次用户提问以前的工具结果压短；2. 还超过 budget 字，就从最早的一轮开始整轮丢掉（至少留最后一轮）
    public static func fit(_ messages: [AgentMessage], budget: Int = 40000) -> [AgentMessage] {
        let lastUser = messages.lastIndex(where: \.isUser) ?? 0
        var out = messages.enumerated().map { i, m -> AgentMessage in
            if i < lastUser, case .tool(let id, let name, let result) = m, result.count > oldToolResult {
                return .tool(id: id, name: name, result: clip(result, oldToolResult))
            }
            return m
        }
        while out.reduce(0, { $0 + $1.size }) > budget {
            // 第二轮从哪开始；只剩一轮就不再丢了
            guard let next = out.indices.dropFirst().first(where: { out[$0].isUser }) else { break }
            out.removeSubrange(0..<next)
        }
        return out
    }
}
