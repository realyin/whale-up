import XCTest
@testable import WhaleUpCore

final class LogicalDayTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testBeforeFourAMCountsAsPreviousDay() {
        XCTAssertEqual(LogicalDay.of(at(21, 0, 30), calendar: cal), at(20, 0))
        XCTAssertEqual(LogicalDay.of(at(21, 3, 59), calendar: cal), at(20, 0))
        XCTAssertEqual(LogicalDay.of(at(21, 4, 0), calendar: cal), at(21, 0))
        XCTAssertEqual(LogicalDay.of(at(21, 23, 0), calendar: cal), at(21, 0))
        XCTAssertEqual(DayKey.string(at(21, 2), calendar: cal), "2026-10-20")
    }

    func testDayLabelIsStable() {
        XCTAssertEqual(LogicalDay.of(at(21, 0), calendar: cal), at(21, 0))
        XCTAssertEqual(LogicalDay.of(LogicalDay.of(at(21, 2), calendar: cal), calendar: cal), at(20, 0))
    }

    func testRangeRunsFromFourToFour() {
        let r = LogicalDay.range(at(20, 0), calendar: cal)
        XCTAssertEqual(r.start, at(20, 4))
        XCTAssertEqual(r.end, at(21, 4))
    }

    func testUsageAfterMidnightGoesToPreviousDay() {
        var stats = UsageStats()
        stats.add("site:bilibili.com", seconds: 600, at: at(20, 23), calendar: cal)
        stats.add("site:bilibili.com", seconds: 300, at: at(21, 1), calendar: cal)
        let items = stats.items(on: at(20, 0), config: Config(), calendar: cal)
        XCTAssertEqual(items.first?.seconds, 900)
    }
}
