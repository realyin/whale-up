import XCTest
@testable import FocusGuardCore

final class ReportContentTests: XCTestCase {
    func testDailyPromptAsksForShortStructuredOutput() {
        let p = DigestPrompt.make(day: Date(), views: [], reasons: [], config: Config())
        XCTAssertTrue(p.system.contains("不要复述"))
        XCTAssertTrue(p.system.contains("20 字"))
        XCTAssertTrue(p.system.contains("最多 3 条"))
        XCTAssertFalse(p.system.contains("## "), "不再要求 Markdown 长文")
        XCTAssertEqual((DailyReport.schema["required"] as! [String]).sorted(), ["findings", "headline", "tomorrow"])
    }

    func testDailyReportParsesAndTrims() throws {
        let raw = #"{"headline":"深夜刷抖音是今天唯一的失守","findings":["23 点后连看 8 个搞笑视频","学习视频只看了开头","a","b"],"tomorrow":"23:30 把手机放客厅"}"#
        let r = try DailyReport.parse(raw)
        XCTAssertEqual(r.findings.count, 3, "最多 3 条")
        XCTAssertEqual(r.headline, "深夜刷抖音是今天唯一的失守")
    }

    func testDailyReportMarkdownIsCompact() {
        let r = DailyReport(headline: "结论", findings: ["发现一", "发现二"], tomorrow: "行动")
        XCTAssertEqual(r.markdown, "**结论**\n\n- 发现一\n- 发现二\n\n明天：行动")
    }

    func testWeeklyReportRoundTrip() throws {
        let raw = #"{"headline":"一周只失守一次","patterns":["失守都在 0 点后"],"cause":"你说的是“累了”","actions":["23:50 设闹钟"],"alternative":"","commitment":"0 点后不打开 B 站"}"#
        let r = try WeeklyReport.parse(raw)
        XCTAssertEqual(r.patterns, ["失守都在 0 点后"])
        XCTAssertFalse(r.markdown.contains("替代"), "空的部分不输出")
        XCTAssertTrue(r.markdown.contains("下周承诺：0 点后不打开 B 站"))
        let p = WeeklyPrompt.make(week: Week(containing: Date()), days: [], config: Config())
        XCTAssertTrue(p.system.contains("不要猜测"))
    }

    func testLegacyMarkdownDigestStillDisplays() {
        let d = Digest(day: "2026-10-20", text: "## 今天概况\n旧格式", model: "m")
        XCTAssertNil(d.daily)
        XCTAssertNil(d.weekly)
    }
}
