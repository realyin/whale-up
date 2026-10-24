import XCTest
@testable import WhaleUpCore

final class ForceCloserTests: XCTestCase {
    var config: Config = {
        var c = Config()
        c.forceCloseEnabled = true
        c.forceCloseMinutes = 10
        return c
    }()
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    /// 某天的几点几分（上海时间）
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testDisabledNeverActs() {
        config.forceCloseEnabled = false
        var f = ForceCloser()
        XCTAssertNil(f.record(onSite: true, usedToday: 3600, now: at(20, 20), config: config, calendar: cal))
    }

    func testWarnsOneMinuteBeforeThenCloses() {
        var f = ForceCloser()
        XCTAssertNil(f.record(onSite: true, usedToday: 8 * 60, now: at(20, 20), config: config, calendar: cal))
        XCTAssertEqual(f.record(onSite: true, usedToday: 9 * 60, now: at(20, 20, 1), config: config, calendar: cal), .warn)
        XCTAssertNil(f.record(onSite: true, usedToday: 9.5 * 60, now: at(20, 20, 2), config: config, calendar: cal))
        XCTAssertEqual(f.record(onSite: true, usedToday: 10 * 60, now: at(20, 20, 3), config: config, calendar: cal), .close)
    }

    /// 今天已经看够了：现在正在看就关，之后不管多久再打开都关（没有“过 15 分钟又能看”）
    func testOverLimitClosesEveryTimeForRestOfDay() {
        var f = ForceCloser()
        for (h, m) in [(20, 0), (20, 30), (22, 0), (23, 59), (2, 0), (3, 59)] {
            let day = h < 4 ? 21 : 20
            XCTAssertEqual(f.record(onSite: true, usedToday: 12 * 60, now: at(day, h, m), config: config, calendar: cal), .close)
        }
    }

    func testOffSiteDoesNothing() {
        var f = ForceCloser()
        XCTAssertNil(f.record(onSite: false, usedToday: 3600, now: at(20, 20), config: config, calendar: cal))
    }

    func testGrantGivesExtraTimeOnlyForToday() {
        var f = ForceCloser()
        XCTAssertEqual(f.record(onSite: true, usedToday: 12 * 60, now: at(20, 21), config: config, calendar: cal), .close)
        f.grant(minutes: 10, now: at(20, 21), calendar: cal)
        XCTAssertNil(f.record(onSite: true, usedToday: 12 * 60, now: at(20, 21, 1), config: config, calendar: cal))
        XCTAssertEqual(f.record(onSite: true, usedToday: 20 * 60, now: at(20, 21, 9), config: config, calendar: cal), .close)
        // 第二天（凌晨 4 点以后）加的时间清零
        XCTAssertEqual(f.extraSeconds, 600)
        _ = f.record(onSite: false, usedToday: 0, now: at(21, 4, 1), config: config, calendar: cal)
        XCTAssertEqual(f.extraSeconds, 0)
    }

    /// 凌晨 4 点前还算前一天，加的时间还在
    func testGrantSurvivesPastMidnightUntilDayStart() {
        var f = ForceCloser()
        f.grant(minutes: 10, now: at(20, 23), calendar: cal)
        XCTAssertNil(f.record(onSite: true, usedToday: 15 * 60, now: at(21, 1), config: config, calendar: cal))
        XCTAssertEqual(f.extraSeconds, 600)
    }
}
