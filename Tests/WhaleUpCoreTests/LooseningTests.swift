import XCTest
@testable import WhaleUpCore

final class LooseningTests: XCTestCase {
    var base: Config = {
        var c = Config()
        c.forceCloseEnabled = true
        c.forceCloseMinutes = 10
        c.forceCloseSites = ["douyin.com", "bilibili.com"]
        c.dailyBudgetMinutes = 30
        c.budgetCloses = true
        return c
    }()

    func testTighteningNeedsNoCode() {
        var c = base
        c.forceCloseMinutes = 5
        c.forceCloseSites.append("kuaishou.com")
        c.dailyBudgetMinutes = 20
        XCTAssertEqual(c.loosenings(from: base), [])
    }

    func testLooseningsAreListed() {
        var c = base
        c.forceCloseMinutes = 20
        c.forceCloseSites = ["douyin.com"]
        XCTAssertEqual(c.loosenings(from: base).count, 2)
        var off = base
        off.forceCloseEnabled = false
        XCTAssertEqual(off.loosenings(from: base), ["关掉强制关闭"])
        var noBudget = base
        noBudget.dailyBudgetMinutes = 0
        XCTAssertEqual(noBudget.loosenings(from: base), ["取消每日额度"])
    }

    func testRandomCodeFormatAndMatching() {
        let code = RandomCode.make()
        XCTAssertEqual(code.filter { $0 != "-" }.count, RandomCode.length)
        XCTAssertTrue(RandomCode.matches(code.lowercased().replacingOccurrences(of: "-", with: " "), code))
        XCTAssertFalse(RandomCode.matches(String(code.dropLast()), code))
        XCTAssertFalse(RandomCode.matches("", code))
    }

    func testGrantsAreCappedPerDay() {
        var f = ForceCloser()
        XCTAssertTrue(f.adjust(minutes: 5, config: base))
        XCTAssertTrue(f.adjust(minutes: 5, config: base))
        XCTAssertFalse(f.adjust(minutes: 5, config: base))
        XCTAssertEqual(f.grantsLeft(), 0)
        // 少看不受限制
        XCTAssertTrue(f.adjust(minutes: -5, config: base))
    }

    func testOldSavedStateStillDecodes() throws {
        let old = #"{"extraSeconds":300,"day":"2026-10-25","warned":false}"#
        let f = try JSONDecoder().decode(ForceCloser.self, from: Data(old.utf8))
        XCTAssertEqual(f.extraSeconds, 300)
        XCTAssertEqual(f.grantsToday, 0)
    }
}
