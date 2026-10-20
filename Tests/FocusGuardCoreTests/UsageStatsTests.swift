import XCTest
@testable import FocusGuardCore

final class UsageStatsTests: XCTestCase {
    let config = Config()
    let cal = Calendar(identifier: .gregorian)

    func date(day: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testKeyUsesDomainForBrowserAndNameForApps() {
        let site = Activity(appName: "Safari", bundleID: "com.apple.Safari", url: "https://www.zhihu.com/question/1")
        let app = Activity(appName: "微信", bundleID: "com.tencent.xinWeChat")
        let blank = Activity(appName: "Google Chrome", bundleID: "com.google.Chrome", url: "chrome://newtab/")
        XCTAssertEqual(UsageStats.key(for: site, config: config), "site:zhihu.com")
        XCTAssertEqual(UsageStats.key(for: app, config: config), "app:微信")
        XCTAssertEqual(UsageStats.key(for: blank, config: config), "app:Google Chrome")
    }

    func testKeyKeepsMatchedRuleWithPath() {
        let shorts = Activity(appName: "Safari", bundleID: "com.apple.Safari", url: "https://www.youtube.com/shorts/x")
        XCTAssertEqual(UsageStats.key(for: shorts, config: config), "site:youtube.com/shorts")
    }

    func testAILabelSplitsSiteTimeByNutrition() {
        var c = config
        c.llm.enabled = true
        let bili = Activity(appName: "Chrome", bundleID: "com.google.Chrome", url: "https://www.bilibili.com/video/BV1")
        let learning = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "", model: "m")
        let fun = ContentLabel(isJunk: true, nutrition: 1, category: "娱乐", reason: "", model: "m")
        let goodKey = UsageStats.key(for: bili, config: c, label: learning)
        XCTAssertEqual(goodKey, "site:bilibili.com · 有营养")
        XCTAssertEqual(UsageStats.key(for: bili, config: c, label: fun), "site:bilibili.com")

        let other = Activity(appName: "Chrome", bundleID: "com.google.Chrome", url: "https://www.zhihu.com/q")
        let badKey = UsageStats.key(for: other, config: c, label: fun)
        XCTAssertEqual(badKey, "site:zhihu.com · 没营养")

        var s = UsageStats()
        s.add(goodKey, seconds: 600, at: date(day: 20), calendar: cal)
        s.add(badKey, seconds: 60, at: date(day: 20), calendar: cal)
        let items = s.items(on: date(day: 20), config: c, calendar: cal)
        XCTAssertEqual(items.first { $0.key == goodKey }?.isJunk, false)
        XCTAssertEqual(items.first { $0.key == badKey }?.isJunk, true)
    }

    func testLabelIgnoredInKeyWhenAIDisabled() {
        let bili = Activity(appName: "Chrome", bundleID: "com.google.Chrome", url: "https://www.bilibili.com/video/BV1")
        let learning = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "", model: "m")
        XCTAssertEqual(UsageStats.key(for: bili, config: config, label: learning), "site:bilibili.com")
    }

    func testAccumulatesPerDayAndSortsByTime() {
        var s = UsageStats()
        s.add("site:bilibili.com", seconds: 300, at: date(day: 20), calendar: cal)
        s.add("site:zhihu.com", seconds: 60, at: date(day: 20), calendar: cal)
        s.add("site:bilibili.com", seconds: 120, at: date(day: 20, hour: 22), calendar: cal)
        s.add("site:bilibili.com", seconds: 999, at: date(day: 19), calendar: cal)

        let items = s.items(on: date(day: 20), config: config, calendar: cal)
        XCTAssertEqual(items.map(\.name), ["bilibili.com", "zhihu.com"])
        XCTAssertEqual(items.first?.seconds, 420)
        XCTAssertEqual(items.first?.isJunk, true)
        XCTAssertEqual(items.last?.isJunk, false)
    }

    func testJunkTotalsForRecentDays() {
        var s = UsageStats()
        s.add("site:bilibili.com", seconds: 600, at: date(day: 20), calendar: cal)
        s.add("app:Xcode", seconds: 3600, at: date(day: 20), calendar: cal)
        s.add("app:抖音", seconds: 120, at: date(day: 18), calendar: cal)
        let totals = s.junkTotals(days: 3, endingAt: date(day: 20), config: config, calendar: cal)
        XCTAssertEqual(totals.map(\.seconds), [120, 0, 600])
    }

    func testRemoveDayAndSite() {
        var s = UsageStats()
        s.add("site:bilibili.com", seconds: 60, at: date(day: 20), calendar: cal)
        s.add("site:bilibili.com · 有营养", seconds: 60, at: date(day: 19), calendar: cal)
        s.add("site:zhihu.com", seconds: 60, at: date(day: 19), calendar: cal)
        s.removeDay(date(day: 20), calendar: cal)
        XCTAssertTrue(s.items(on: date(day: 20), config: config, calendar: cal).isEmpty)
        s.removeSite("bilibili.com")
        XCTAssertEqual(s.items(on: date(day: 19), config: config, calendar: cal).map(\.name), ["zhihu.com"])
    }

    func testPruneDropsOldDays() {
        var s = UsageStats()
        s.add("site:a.com", seconds: 1, at: date(day: 1), calendar: cal)
        s.add("site:a.com", seconds: 1, at: date(day: 20), calendar: cal)
        s.prune(keepingDays: 7, now: date(day: 20), calendar: cal)
        XCTAssertTrue(s.items(on: date(day: 1), config: config, calendar: cal).isEmpty)
        XCTAssertFalse(s.items(on: date(day: 20), config: config, calendar: cal).isEmpty)
    }
}
