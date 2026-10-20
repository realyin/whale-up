import XCTest
@testable import FocusGuardCore

final class SuggestionTests: XCTestCase {
    func testPromptsSayItIsAComputerAssistantWithCurrentSettings() {
        var c = Config()
        c.dailyBudgetMinutes = 0
        c.forceCloseEnabled = false
        let daily = DigestPrompt.make(day: Date(), views: [], reasons: [], config: c).system
        let weekly = WeeklyPrompt.make(week: Week(containing: Date()), days: [], config: c).system
        for p in [daily, weekly] {
            XCTAssertTrue(p.contains("电脑"))
            XCTAssertTrue(p.contains("不要提手机"))
            XCTAssertTrue(p.contains("每日额度：未设置"), p)
            XCTAssertTrue(p.contains("强制关闭：关闭"))
            XCTAssertTrue(p.contains("dailyBudget"))
        }
        let nudge = NudgePrompt.make(nudge: Nudge(reason: "douyin.com", appName: "Chrome", sessionMinutes: 20, todayMinutes: 30,
                                                  isNight: true, count: 1),
                                     recentViews: [], reasons: [], outcomes: nil, hourMinute: "23:00").system
        XCTAssertTrue(nudge.contains("电脑"))
    }

    func testApplyingSuggestions() {
        var c = Config()
        c.forceCloseEnabled = false
        c.forceCloseSites = []

        let budget = Suggestion(kind: .dailyBudget, site: "", minutes: 30)
        XCTAssertEqual(budget.title(for: c), "每日额度设为 30 分钟")
        budget.apply(to: &c)
        XCTAssertEqual(c.dailyBudgetMinutes, 30)
        XCTAssertNil(budget.title(for: c), "已经是这个设置，就不再显示按钮")

        let force = Suggestion(kind: .forceCloseSite, site: "https://www.douyin.com/?x=1", minutes: 0)
        XCTAssertEqual(force.title(for: c), "强制关闭 douyin.com")
        force.apply(to: &c)
        XCTAssertTrue(c.forceCloseEnabled)
        XCTAssertEqual(c.forceCloseSites, ["douyin.com"])
        XCTAssertNil(force.title(for: c))

        let pause = Suggestion(kind: .pauseBeforeJunk, site: "", minutes: 0)
        pause.apply(to: &c)
        XCTAssertTrue(c.pauseBeforeJunk)

        let night = Suggestion(kind: .nightLimit, site: "", minutes: 3)
        night.apply(to: &c)
        XCTAssertEqual(c.nightLimitMinutes, 3)
    }

    func testNoneOrInvalidSuggestionHasNoButton() {
        let c = Config()
        XCTAssertNil(Suggestion(kind: .none, site: "", minutes: 0).title(for: c))
        XCTAssertNil(Suggestion(kind: .dailyBudget, site: "", minutes: 0).title(for: c))
        XCTAssertNil(Suggestion(kind: .forceCloseSite, site: "不是网址", minutes: 0).title(for: c))
    }

    func testReportsCarryOptionalSetting() throws {
        let raw = #"{"headline":"h","findings":[],"tomorrow":"t","setting":{"kind":"dailyBudget","site":"","minutes":30}}"#
        XCTAssertEqual(try DailyReport.parse(raw).setting?.minutes, 30)
        let old = #"{"headline":"h","findings":[],"tomorrow":"t"}"#
        XCTAssertNil(try DailyReport.parse(old).setting)
        XCTAssertTrue((DailyReport.schema["required"] as! [String]).contains("setting"))
        XCTAssertTrue((WeeklyReport.schema["required"] as! [String]).contains("setting"))
    }
}
