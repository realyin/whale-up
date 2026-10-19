import XCTest
@testable import FocusGuardCore

final class SmartNudgeTests: XCTestCase {
    let nudge = Nudge(reason: "douyin.com", appName: "Google Chrome", sessionMinutes: 25, todayMinutes: 70, isNight: true, count: 2)

    func view(_ title: String, _ category: String, junk: Bool) -> ContentView {
        var v = ContentView(viewId: title, url: "https://www.douyin.com/?recommend=1", title: title, author: "某人",
                            kind: "video", startedAt: 1, endedAt: 2, activeSeconds: 60)
        v.label = ContentLabel(isJunk: junk, nutrition: junk ? 1 : 4, category: category, reason: "", model: "m", hook: "搞笑")
        return v
    }

    func testPromptUsesSessionContentAndHistory() {
        let p = NudgePrompt.make(nudge: nudge, recentViews: [view("沙雕合集1", "搞笑", junk: true), view("沙雕合集2", "搞笑", junk: true)],
                                 reasons: [.tired, .tired], outcomes: "接受 3 次，再刷 5 次", hourMinute: "23:40")
        XCTAssertTrue(p.user.contains("沙雕合集1"))
        XCTAssertTrue(p.user.contains("连续 25 分钟"))
        XCTAssertTrue(p.user.contains("23:40"))
        XCTAssertTrue(p.user.contains("深夜"))
        XCTAssertTrue(p.user.contains("😴 累了"))
        XCTAssertTrue(p.user.contains("接受 3 次"))
        XCTAssertTrue(p.user.contains("第 2 次提醒"))
    }

    func testSpecIsShortAndStructured() {
        let p = NudgePrompt.make(nudge: nudge, recentViews: [], reasons: [], outcomes: nil, hourMinute: "14:00")
        var llm = LLMConfig()
        llm.taggingModel = "fast-model"
        let spec = NudgePrompt.spec(p, llm: llm)
        XCTAssertEqual(spec.model, "fast-model")
        XCTAssertEqual(spec.effort, "low")
        XCTAssertNotNil(spec.jsonSchema)
        XCTAssertTrue(spec.jsonExample?.contains("body") == true)
    }

    func testParsesNudgeText() throws {
        let json = #"{"choices":[{"message":{"content":"{\"emoji\":\"🌙\",\"title\":\"该睡了\",\"body\":\"已经连看 6 个沙雕视频了\"}"}}]}"#
        let t = try NudgePrompt.parse(Data(json.utf8), provider: .deepseek)
        XCTAssertEqual(t, NudgeText(emoji: "🌙", title: "该睡了", body: "已经连看 6 个沙雕视频了"))
    }

    func testOverlongOrEmptyOutputRejected() {
        let empty = #"{"choices":[{"message":{"content":"{\"emoji\":\"\",\"title\":\"\",\"body\":\"\"}"}}]}"#
        XCTAssertThrowsError(try NudgePrompt.parse(Data(empty.utf8), provider: .deepseek))
    }
}
