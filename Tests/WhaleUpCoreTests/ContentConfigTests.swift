import XCTest
@testable import WhaleUpCore

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

    func testSensitiveSitesAreNeverRecordedEvenWithScopeAll() {
        var c = Config()
        c.contentScope = .all
        XCTAssertFalse(c.shouldRecordContent(url: "https://mybank.icbc.com.cn/icbc/perbank/index.jsp"))
        XCTAssertFalse(c.shouldRecordContent(url: "https://mail.google.com/mail/u/0/#inbox"))
        XCTAssertFalse(c.shouldRecordContent(url: "https://www.haodf.com/doctor/1.html"))
        XCTAssertFalse(c.shouldRecordContent(url: "https://etax.chinatax.gov.cn/"))
        XCTAssertTrue(c.shouldRecordContent(url: "https://www.google.com/search?q=swift"), "只排除邮箱，不排除 Google 搜索")
        XCTAssertTrue(c.isSensitive(url: "https://www.alipay.com/"))
    }

    func testSensitiveBeatsJunkList() {
        var c = Config()
        c.sensitiveSites.append("bilibili.com")
        XCTAssertFalse(c.shouldRecordContent(url: "https://www.bilibili.com/video/BV1"))
    }

    func testSensitiveSitesHiddenInUsageStats() {
        var c = Config()
        c.contentScope = .all
        let bank = Activity(appName: "Safari", bundleID: "com.apple.Safari", url: "https://www.cmbchina.com/personal")
        XCTAssertEqual(UsageStats.key(for: bank, config: c), "site:" + UsageStats.sensitiveName)
    }

    func testOldConfigFileWithoutNewFieldsStillLoads() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"daytimeLimitMinutes": 15}"#.utf8))
        XCTAssertEqual(c.daytimeLimitMinutes, 15)
        XCTAssertEqual(c.contentScope, .junk)
        XCTAssertEqual(c.llm, LLMConfig())
        XCTAssertFalse(c.sensitiveSites.isEmpty)
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
