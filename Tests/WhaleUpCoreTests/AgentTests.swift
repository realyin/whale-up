import XCTest
@testable import WhaleUpCore

final class ForceDecisionTests: XCTestCase {
    var config: Config = {
        var c = Config()
        c.forceCloseEnabled = true
        c.llm.enabled = true
        return c
    }()
    let good = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "英语听力", model: "m")
    let junk = ContentLabel(isJunk: true, nutrition: 1, category: "搞笑", reason: "段子", model: "m")

    func make(rule: String? = "bilibili.com", browsing: Bool = false, waiting: Bool = false, label: ContentLabel? = nil,
              used: Double = 3600, limit: Double = 1800) -> ForceDecision {
        ForceDecision.make(rule: rule, browsing: browsing, awaitingLabel: waiting, label: label, config: config, used: used, limit: limit)
    }

    func testOrderOfReasons() {
        XCTAssertEqual(make(rule: nil), .notListed)
        XCTAssertEqual(make(browsing: true, label: junk).code, "browsePage")
        XCTAssertEqual(make(waiting: true).code, "awaitingLabel")
        XCTAssertEqual(make(label: good).code, "nutritious")
        XCTAssertEqual(make(label: junk, used: 60).code, "underLimit")
        XCTAssertEqual(make(label: junk).code, "close")
        // 没判断出来（等过了 30 秒）按没营养算
        XCTAssertEqual(make(label: nil).code, "close")
    }

    func testOnlyJunkCountsTowardClosing() {
        XCTAssertTrue(make(label: junk).isJunkOnListedSite)
        XCTAssertTrue(make(label: junk, used: 0).isJunkOnListedSite)
        XCTAssertFalse(make(label: good).isJunkOnListedSite)
        XCTAssertFalse(make(waiting: true).isJunkOnListedSite)
        XCTAssertFalse(make(browsing: true).isJunkOnListedSite)
    }

    func testDisabledForceCloseExplainsItself() {
        config.forceCloseEnabled = false
        let d = make(label: junk)
        XCTAssertEqual(d.code, "overLimitDisabled")
        XCTAssertTrue(d.explanation.contains("没开"))
    }

    func testAIOffIgnoresLabel() {
        config.llm.enabled = false
        XCTAssertEqual(make(label: good).code, "close")
    }
}

final class EventLogTests: XCTestCase {
    var store: ContentStore!
    var path: String!

    override func setUpWithError() throws {
        path = NSTemporaryDirectory() + "fg-events-\(UUID().uuidString).sqlite"
        store = try ContentStore(path: path)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(atPath: path)
    }

    func testFilterAndOrder() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try store.addEvent(AppEvent(at: t, kind: .decision, site: "bilibili.com", url: "https://www.bilibili.com/video/BV1",
                                    title: "英语听力", detail: "AI 还在判断"))
        try store.addEvent(AppEvent(at: t + 10, kind: .action, site: "bilibili.com", url: "https://www.bilibili.com/video/BV1",
                                    title: "英语听力", detail: "强制关闭：关掉了"))
        try store.addEvent(AppEvent(at: t + 20, kind: .error, detail: "脚本出错"))
        let all = try store.events(from: t, to: t + 60)
        XCTAssertEqual(all.map(\.kind), [.error, .action, .decision])
        XCTAssertEqual(try store.events(from: t, to: t + 60, kind: .action).count, 1)
        XCTAssertEqual(try store.events(from: t, to: t + 60, site: "bilibili.com").count, 2)
        XCTAssertEqual(try store.events(from: t, to: t + 60, keyword: "英语").count, 2)
        XCTAssertEqual(try store.events(from: t, to: t + 60, limit: 1).first?.detail, "脚本出错")
    }

    func testDeleteDayAndSiteRemoveEvents() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try store.addEvent(AppEvent(at: t, kind: .decision, site: "bilibili.com", detail: "a"))
        try store.addEvent(AppEvent(at: t + 100_000, kind: .decision, site: "x.com", detail: "b"))
        try store.deleteSite("bilibili.com")
        XCTAssertEqual(try store.events(from: t - 1, to: t + 200_000).map(\.detail), ["b"])
        try store.deleteDay(from: t + 99_000, to: t + 101_000, dayKey: "x")
        XCTAssertTrue(try store.events(from: t - 1, to: t + 200_000).isEmpty)
    }

    func testRelabelAndKeywordViews() throws {
        let v = ContentView(viewId: "v1", url: "https://www.bilibili.com/video/BV1", title: "坚持这样练英语听力", author: "Lee",
                            tags: [], kind: "video", startedAt: 1_800_000_000, endedAt: 1_800_000_010, activeSeconds: 10)
        try store.upsert(v)
        try store.setLabel(forURL: v.url, label: ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "改正", model: "user"))
        let found = try store.views(matching: "英语", from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2e9))
        XCTAssertEqual(found.first?.label?.reason, "改正")
        XCTAssertEqual(try store.label(forURL: v.url)?.isJunk, false)
    }
}

final class AgentWireTests: XCTestCase {
    let messages: [AgentMessage] = [
        .user("今天看了多久？"),
        .assistant(text: "", reasoning: "要查统计", calls: [AgentToolCall(id: "c1", name: "get_usage", arguments: "{}"),
                                                         AgentToolCall(id: "c2", name: "get_status", arguments: "{\"a\":1}")]),
        .tool(id: "c1", name: "get_usage", result: "B 站 20 分钟"),
        .tool(id: "c2", name: "get_status", result: "ok"),
    ]

    func body(_ provider: LLMProvider) throws -> [String: Any] {
        var llm = LLMConfig()
        llm.provider = provider
        let tools = [AgentTool(name: "get_usage", description: "查时长")]
        let req = try AgentWire.request(system: "sys", messages: messages, tools: tools, llm: llm, apiKey: "k", model: "m")
        return try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    }

    func testDeepSeekPassesReasoningBackWithinTurn() throws {
        let b = try body(.deepseek)
        let msgs = b["messages"] as! [[String: Any]]
        XCTAssertEqual(msgs.map { $0["role"] as! String }, ["system", "user", "assistant", "tool", "tool"])
        XCTAssertEqual(msgs[2]["reasoning_content"] as? String, "要查统计")
        XCTAssertEqual((msgs[2]["tool_calls"] as! [[String: Any]]).count, 2)
        XCTAssertEqual(msgs[3]["tool_call_id"] as? String, "c1")
        XCTAssertNotNil(b["tools"])
    }

    func testOldReasoningNotSent() {
        let later = messages + [.assistant(text: "20 分钟", reasoning: "总结", calls: []), .user("那昨天呢")]
        let msgs = AgentWire.openAIMessages(later, withReasoning: true)
        XCTAssertNil(msgs[1]["reasoning_content"])
    }

    func testAnthropicGroupsToolResults() throws {
        let b = try body(.anthropic)
        let msgs = b["messages"] as! [[String: Any]]
        XCTAssertEqual(msgs.map { $0["role"] as! String }, ["user", "assistant", "user"])
        XCTAssertEqual((msgs[2]["content"] as! [[String: Any]]).count, 2)
        let use = (msgs[1]["content"] as! [[String: Any]])[1]
        XCTAssertEqual((use["input"] as? [String: Any])?["a"] as? Int, 1)
        XCTAssertEqual(b["system"] as? String, "sys")
    }

    func testParseOpenAIToolCalls() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"","reasoning_content":"想想","tool_calls":[{"id":"x","type":"function","function":{"name":"get_usage","arguments":"{\"day\":\"2026-10-25\"}"}}]}}]}"#
        let r = try AgentWire.parse(Data(json.utf8), provider: .deepseek)
        XCTAssertEqual(r.calls, [AgentToolCall(id: "x", name: "get_usage", arguments: #"{"day":"2026-10-25"}"#)])
        XCTAssertEqual(r.reasoning, "想想")
    }

    func testParseAnthropicToolUse() throws {
        let json = #"{"content":[{"type":"text","text":"我查一下"},{"type":"tool_use","id":"t1","name":"get_usage","input":{"day":"x"}}],"stop_reason":"tool_use"}"#
        let r = try AgentWire.parse(Data(json.utf8), provider: .anthropic)
        XCTAssertEqual(r.text, "我查一下")
        XCTAssertEqual(r.calls.first?.name, "get_usage")
        XCTAssertEqual(r.calls.first?.arguments, #"{"day":"x"}"#)
    }

    func testParseError() {
        XCTAssertThrowsError(try AgentWire.parse(Data(#"{"error":{"message":"bad key"}}"#.utf8), provider: .deepseek))
    }
}

final class AgentMemoryTests: XCTestCase {
    func turn(_ q: String, result: Int) -> [AgentMessage] {
        [.user(q), .assistant(text: "", reasoning: nil, calls: [AgentToolCall(id: q, name: "t", arguments: "{}")]),
         .tool(id: q, name: "t", result: String(repeating: "字", count: result)), .assistant(text: "答", reasoning: nil, calls: [])]
    }

    func testOldToolResultsShrinkCurrentKept() {
        let m = turn("一", result: 3000) + turn("二", result: 3000)
        let fit = AgentMemory.fit(m)
        guard case .tool(_, _, let old) = fit[2], case .tool(_, _, let new) = fit[6] else { return XCTFail() }
        XCTAssertLessThan(old.count, 500)
        XCTAssertEqual(new.count, 3000)
    }

    func testDropsOldestTurnsButKeepsLast() {
        let m = turn("一", result: 100) + turn("二", result: 100) + turn("三", result: 5000)
        let fit = AgentMemory.fit(m, budget: 5200)
        XCTAssertEqual(fit.first, .user("三"))
        // 只剩一轮也超了，不能再丢
        XCTAssertEqual(AgentMemory.fit(turn("一", result: 9000), budget: 10).count, 4)
    }

    func testClip() {
        XCTAssertEqual(AgentMemory.clip("短"), "短")
        XCTAssertTrue(AgentMemory.clip(String(repeating: "a", count: 7000)).hasSuffix("缩小范围再查）"))
    }
}
