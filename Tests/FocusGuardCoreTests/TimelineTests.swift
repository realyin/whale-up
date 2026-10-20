import XCTest
@testable import FocusGuardCore

final class TimelineTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    var config: Config = {
        var c = Config()
        c.llm.enabled = true
        return c
    }()

    func t(_ h: Int, _ m: Int) -> Double {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: h, minute: m))!.timeIntervalSince1970
    }

    func v(_ id: String, _ site: String, _ start: Double, minutes: Double, junk: Bool) -> ContentView {
        var view = ContentView(viewId: id, url: "https://www.\(site)/\(id)", title: "标题\(id)", kind: "video",
                               startedAt: start, endedAt: start + minutes * 60, activeSeconds: minutes * 60)
        view.label = ContentLabel(isJunk: junk, nutrition: junk ? 1 : 4, category: junk ? "娱乐" : "学习", reason: "", model: "m")
        return view
    }

    func testConsecutiveSameSiteViewsMergeIntoOneSession() {
        let views = [
            v("1", "douyin.com", t(23, 0), minutes: 1, junk: true),
            v("2", "douyin.com", t(23, 1), minutes: 1, junk: true),
            v("3", "douyin.com", t(23, 3), minutes: 2, junk: true),
            v("4", "bilibili.com", t(23, 10), minutes: 10, junk: false),
            v("5", "douyin.com", t(23, 30), minutes: 1, junk: true),
        ]
        let day = Timeline.build(views: views.shuffled(), config: config, calendar: cal)
        XCTAssertEqual(day.sessions.map(\.site), ["douyin.com", "bilibili.com", "douyin.com"])
        XCTAssertEqual(day.sessions[0].items.map(\.viewId), ["1", "2", "3"])
        XCTAssertEqual(day.sessions[0].activeSeconds, 240)
        XCTAssertTrue(day.sessions[0].isJunk)
        XCTAssertFalse(day.sessions[1].isJunk)
    }

    func testLongGapSplitsSessions() {
        let views = [v("1", "douyin.com", t(9, 0), minutes: 1, junk: true),
                     v("2", "douyin.com", t(9, 20), minutes: 1, junk: true)]
        XCTAssertEqual(Timeline.build(views: views, config: config, calendar: cal).sessions.count, 2)
    }

    func testMixedSessionIsJunkByMajorityOfTime() {
        let views = [v("1", "bilibili.com", t(20, 0), minutes: 2, junk: true),
                     v("2", "bilibili.com", t(20, 2), minutes: 8, junk: false)]
        let s = Timeline.build(views: views, config: config, calendar: cal).sessions[0]
        XCTAssertFalse(s.isJunk)
        XCTAssertEqual(s.junkSeconds, 120)
    }

    func testHourlyTotals() {
        let views = [v("1", "douyin.com", t(23, 0), minutes: 5, junk: true),
                     v("2", "bilibili.com", t(9, 0), minutes: 10, junk: false)]
        let hours = Timeline.build(views: views, config: config, calendar: cal).hours
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[23].junkSeconds, 300)
        XCTAssertEqual(hours[9].goodSeconds, 600)
        XCTAssertEqual(hours[12].junkSeconds + hours[12].goodSeconds, 0)
    }
}
