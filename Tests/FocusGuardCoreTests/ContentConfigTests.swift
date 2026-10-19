import XCTest
@testable import FocusGuardCore

final class ContentConfigTests: XCTestCase {
    func testDefaultsRecordOnlyJunkSites() {
        let c = Config()
        XCTAssertEqual(c.contentScope, .junk)
        XCTAssertTrue(c.shouldRecordContent(url: "https://www.bilibili.com/video/BV1"))
        XCTAssertFalse(c.shouldRecordContent(url: "https://github.com/"))
    }

    func testForceCloseSitesCountAsJunkForRecording() {
        var c = Config()
        c.forceCloseSites = ["zhihu.com"]
        XCTAssertTrue(c.shouldRecordContent(url: "https://www.zhihu.com/question/1"))
    }

    func testScopeAllRecordsWebPagesButNotInternalPages() {
        var c = Config()
        c.contentScope = .all
        XCTAssertTrue(c.shouldRecordContent(url: "https://github.com/"))
        XCTAssertFalse(c.shouldRecordContent(url: "chrome://settings"))
    }

    func testScopeOffRecordsNothing() {
        var c = Config()
        c.contentScope = .off
        XCTAssertFalse(c.shouldRecordContent(url: "https://www.bilibili.com/"))
    }

    func testOldConfigFileWithoutNewFieldsStillLoads() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"daytimeLimitMinutes": 15}"#.utf8))
        XCTAssertEqual(c.daytimeLimitMinutes, 15)
        XCTAssertEqual(c.contentScope, .junk)
        XCTAssertEqual(c.llm, LLMConfig())
    }

    func testLLMConfigRoundTrips() throws {
        var c = Config()
        c.contentScope = .all
        c.llm = LLMConfig(provider: .ollama, taggingModel: "qwen3:8b", reportModel: "qwen3:32b",
                          baseURL: "http://127.0.0.1:11434")
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c)
    }
}
