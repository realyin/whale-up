import XCTest
@testable import FocusGuardCore

final class DigestTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    var config: Config = {
        var c = Config()
        c.llm.enabled = true
        return c
    }()

    func at(_ h: Int, _ m: Int = 0) -> Double {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: h, minute: m))!.timeIntervalSince1970
    }

    var views: [ContentView] {
        var learn = ContentView(viewId: "1", url: "https://www.bilibili.com/video/a", title: "英语听力练习", author: "老师",
                                kind: "video", startedAt: at(20, 5), endedAt: at(20, 15), activeSeconds: 600)
        learn.label = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "练听力", model: "m")
        var fun = ContentView(viewId: "2", url: "https://www.douyin.com/?recommend=1", title: "搞笑合集 #沙雕",
                              author: "小王", kind: "video", startedAt: at(23, 10), endedAt: at(23, 40),
                              activeSeconds: 1800, backgroundSeconds: 300)
        fun.label = ContentLabel(isJunk: true, nutrition: 1, category: "搞笑", reason: "段子", model: "m")
        let unlabeled = ContentView(viewId: "3", url: "https://www.bilibili.com/video/c", title: "游戏切片",
                                    kind: "video", startedAt: at(23, 45), endedAt: at(23, 50), activeSeconds: 300)
        return [unlabeled, fun, learn]
    }

    func testDigestPromptSummarizesTheDay() {
        let reasons = [NudgeReason(at: Date(timeIntervalSince1970: at(23, 30)), reason: .tired, site: "douyin.com", sessionMinutes: 20)]
        let nudges = [NudgeRecord(at: Date(timeIntervalSince1970: at(23, 30)), site: "douyin.com", sessionMinutes: 20,
                                  isNight: true, byAI: true, title: "t", body: "该睡了", outcome: .snoozed)]
        let p = DigestPrompt.make(day: Date(timeIntervalSince1970: at(12)), views: views, reasons: reasons,
                                  nudges: nudges, config: config, calendar: cal)
        XCTAssertTrue(p.user.contains("今天的劝导：提醒 1 次"), p.user)
        XCTAssertTrue(p.user.contains("2026-10-20"))
        XCTAssertTrue(p.user.contains("没营养内容共 35 分钟"), p.user)  // 30 + 5（未判断的按网站规则算没营养）
        XCTAssertTrue(p.user.contains("23 点"))
        XCTAssertTrue(p.user.contains("搞笑合集"))
        XCTAssertTrue(p.user.contains("🍟"))
        XCTAssertTrue(p.user.contains("🥦"))
        XCTAssertTrue(p.user.contains("后台播放 5 分钟"))
        XCTAssertTrue(p.user.contains("😴 累了"))
        XCTAssertTrue(p.system.contains("往脑子里装了什么"))
        // 按时间先后排列
        XCTAssertLessThan(p.user.range(of: "英语听力")!.lowerBound, p.user.range(of: "搞笑合集")!.lowerBound)
    }

    func testDigestsAreStoredPerDay() throws {
        let path = NSTemporaryDirectory() + "fg-digest-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try ContentStore(path: path)
        XCTAssertNil(try store.digest(day: "2026-10-20"))
        try store.saveDigest(Digest(day: "2026-10-20", text: "第一版", model: "m"))
        try store.saveDigest(Digest(day: "2026-10-20", text: "重写版", model: "m"))
        XCTAssertEqual(try store.digest(day: "2026-10-20")?.text, "重写版")
    }

    func testReportRequestForOpusUsesFallbacksAndTextOutput() throws {
        let llm = LLMConfig()
        let spec = ChatSpec(system: "s", user: "u", model: "claude-opus-5-5", maxTokens: 16000, effort: "medium")
        let req = try LLMRequest.chat(spec, llm: llm, apiKey: "k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil((body["output_config"] as? [String: Any])?["format"])
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
    }

    func testNoFallbacksForHaikuOrCustomBaseURL() throws {
        let haiku = try LLMRequest.chat(ChatSpec(system: "s", user: "u", model: "claude-haiku-5-5", maxTokens: 100),
                                        llm: LLMConfig(), apiKey: "k")
        XCTAssertNil(haiku.value(forHTTPHeaderField: "anthropic-beta"))
        var proxied = LLMConfig()
        proxied.baseURL = "https://proxy.example.com"
        let viaProxy = try LLMRequest.chat(ChatSpec(system: "s", user: "u", model: "claude-opus-5-5", maxTokens: 100),
                                           llm: proxied, apiKey: "k")
        XCTAssertNil(viaProxy.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testTextResponseParsing() throws {
        let anthropic = ###"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"## 今天\n还不错"}],"stop_reason":"end_turn"}"###
        XCTAssertEqual(try LLMResponse.text(Data(anthropic.utf8), provider: .anthropic), "## 今天\n还不错")
        let deepseek = #"{"choices":[{"message":{"content":"小结"}}]}"#
        XCTAssertEqual(try LLMResponse.text(Data(deepseek.utf8), provider: .deepseek), "小结")
    }
}
