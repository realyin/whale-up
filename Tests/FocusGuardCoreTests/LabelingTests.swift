import XCTest
@testable import FocusGuardCore

final class LabelingTests: XCTestCase {
    let view = ContentView(viewId: "v1", url: "https://www.bilibili.com/video/BV1", title: "坚持这样练英语听力",
                           author: "英语老师Lee", tags: ["英语听力", "英语学习"], description: "每天十分钟",
                           kind: "video", startedAt: 1, endedAt: 2, activeSeconds: 30, mediaDuration: 265)

    // MARK: 提示词

    func testPromptContainsContentAndPreferences() {
        var llm = LLMConfig()
        llm.preferences = "编程视频算有营养"
        let p = LabelPrompt.make(for: view, llm: llm)
        XCTAssertTrue(p.system.contains("编程视频算有营养"))
        XCTAssertTrue(p.user.contains("坚持这样练英语听力"))
        XCTAssertTrue(p.user.contains("英语老师Lee"))
        XCTAssertTrue(p.user.contains("bilibili.com"))
        XCTAssertFalse(p.user.contains("BV1"), "不发送完整网址，只发网站")
    }

    // MARK: 请求

    func testAnthropicRequestShape() throws {
        var llm = LLMConfig()
        llm.taggingModel = "claude-haiku-5-5"
        let req = try LLMRequest.labeling(view, llm: llm, apiKey: "sk-test")
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        let output = body["output_config"] as! [String: Any]
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertEqual((output["format"] as! [String: Any])["type"] as? String, "json_schema")
        XCTAssertNil(body["thinking"])
    }

    func testOpenAICompatibleRequestShape() throws {
        let llm = LLMConfig(provider: .openai, taggingModel: "gpt-x", reportModel: "gpt-x", baseURL: "https://example.com/v1/")
        let req = try LLMRequest.labeling(view, llm: llm, apiKey: "k")
        XCTAssertEqual(req.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual((body["response_format"] as! [String: Any])["type"] as? String, "json_schema")
        XCTAssertEqual((body["messages"] as! [[String: Any]]).first?["role"] as? String, "system")
    }

    func testOllamaDefaultsToLocalhostWithoutKey() throws {
        let llm = LLMConfig(provider: .ollama, taggingModel: "qwen3:8b", reportModel: "qwen3:8b", baseURL: "")
        let req = try LLMRequest.labeling(view, llm: llm, apiKey: nil)
        XCTAssertEqual(req.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testDeepSeekUsesJSONObjectModeWithExampleInPrompt() throws {
        let llm = LLMConfig(provider: .deepseek, taggingModel: "deepseek-flash", reportModel: "deepseek-v4-pro", baseURL: "")
        let req = try LLMRequest.labeling(view, llm: llm, apiKey: "sk-ds")
        XCTAssertEqual(req.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-ds")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual((body["response_format"] as! [String: Any])["type"] as? String, "json_object")
        XCTAssertNotNil(body["max_tokens"])
        let system = (body["messages"] as! [[String: Any]])[0]["content"] as! String
        XCTAssertTrue(system.lowercased().contains("json"))
        XCTAssertTrue(system.contains("\"isJunk\""), "json_object 模式要求在提示词里给出示例")
        XCTAssertThrowsError(try LLMRequest.labeling(view, llm: llm, apiKey: nil))
    }

    func testDeepSeekEmptyContentIsAnError() {
        let json = #"{"choices":[{"message":{"content":""}}]}"#
        XCTAssertThrowsError(try LLMResponse.parseLabel(Data(json.utf8), provider: .deepseek, model: "m"))
    }

    func testCloudProvidersNeedKey() {
        XCTAssertThrowsError(try LLMRequest.labeling(view, llm: LLMConfig(), apiKey: nil))
        XCTAssertThrowsError(try LLMRequest.labeling(view, llm: LLMConfig(), apiKey: "  "))
    }

    // MARK: 解析

    func testParsesAnthropicResponseSkippingThinking() throws {
        let json = #"""
        {"content":[{"type":"thinking","thinking":""},
          {"type":"text","text":"{\"isJunk\":false,\"nutrition\":4,\"category\":\"学习\",\"reason\":\"英语听力练习\"}"}],
         "stop_reason":"end_turn","model":"claude-haiku-5-5"}
        """#
        let label = try LLMResponse.parseLabel(Data(json.utf8), provider: .anthropic, model: "claude-haiku-5-5")
        XCTAssertEqual(label.isJunk, false)
        XCTAssertEqual(label.nutrition, 4)
        XCTAssertEqual(label.category, "学习")
        XCTAssertEqual(label.model, "claude-haiku-5-5")
    }

    func testHookIsRequestedAndParsed() throws {
        let p = LabelPrompt.make(for: view, llm: LLMConfig())
        XCTAssertTrue(p.system.contains("hook"))
        XCTAssertTrue((LabelPrompt.schema["required"] as! [String]).contains("hook"))
        XCTAssertTrue(LabelPrompt.example.contains("hook"))
        let json = #"{"choices":[{"message":{"content":"{\"isJunk\":true,\"nutrition\":1,\"category\":\"娱乐\",\"reason\":\"r\",\"hook\":\"猎奇\"}"}}]}"#
        XCTAssertEqual(try LLMResponse.parseLabel(Data(json.utf8), provider: .deepseek, model: "m").hook, "猎奇")
    }

    func testOldLabelWithoutHookStillDecodes() throws {
        let json = #"{"isJunk":true,"nutrition":2,"category":"娱乐","reason":"r","model":"m","labeledAt":1}"#
        XCTAssertNil(try JSONDecoder().decode(ContentLabel.self, from: Data(json.utf8)).hook)
    }

    func testAnthropicRefusalIsAnError() {
        let json = #"{"content":[],"stop_reason":"refusal"}"#
        XCTAssertThrowsError(try LLMResponse.parseLabel(Data(json.utf8), provider: .anthropic, model: "m"))
    }

    func testAnthropicAPIErrorMessageIsSurfaced() {
        let json = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        XCTAssertThrowsError(try LLMResponse.parseLabel(Data(json.utf8), provider: .anthropic, model: "m")) { e in
            XCTAssertTrue("\(e)".contains("invalid x-api-key"))
        }
    }

    func testParsesOpenAIResponse() throws {
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":"{\"isJunk\":true,\"nutrition\":1,\"category\":\"娱乐\",\"reason\":\"搞笑段子\"}"}}]}
        """#
        let label = try LLMResponse.parseLabel(Data(json.utf8), provider: .openai, model: "m")
        XCTAssertTrue(label.isJunk)
        XCTAssertEqual(label.nutrition, 1)
    }

    func testNutritionIsClampedTo1Through5() throws {
        let json = #"{"choices":[{"message":{"content":"{\"isJunk\":true,\"nutrition\":9,\"category\":\"x\",\"reason\":\"y\"}"}}]}"#
        XCTAssertEqual(try LLMResponse.parseLabel(Data(json.utf8), provider: .ollama, model: "m").nutrition, 5)
    }

    // MARK: 判断

    func testLabelOverridesSiteRuleWhenAIEnabled() {
        var config = Config()
        config.llm.enabled = true
        let learning = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "", model: "m")
        let fun = ContentLabel(isJunk: true, nutrition: 1, category: "娱乐", reason: "", model: "m")
        XCTAssertFalse(JunkJudge.isJunk(siteRuleMatched: true, label: learning, config: config))
        XCTAssertTrue(JunkJudge.isJunk(siteRuleMatched: true, label: fun, config: config))
        XCTAssertTrue(JunkJudge.isJunk(siteRuleMatched: true, label: nil, config: config), "还没判断时按网站规则")
        XCTAssertTrue(JunkJudge.isJunk(siteRuleMatched: false, label: fun, config: config), "名单外的网站被判没营养也算")
        XCTAssertFalse(JunkJudge.isJunk(siteRuleMatched: false, label: nil, config: config))
    }

    func testLabelIgnoredWhenAIDisabled() {
        let config = Config()
        let learning = ContentLabel(isJunk: false, nutrition: 5, category: "学习", reason: "", model: "m")
        XCTAssertTrue(JunkJudge.isJunk(siteRuleMatched: true, label: learning, config: config))
    }

    func testOldConfigGetsAIDisabledWithDefaultPreferences() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"llm":{"provider":"anthropic"}}"#.utf8))
        XCTAssertFalse(c.llm.enabled)
        XCTAssertFalse(c.llm.preferences.isEmpty)
    }
}
