import XCTest
@testable import FocusGuardCore

final class ClassifierTests: XCTestCase {
    let config = Config()

    func testBrowserOnShortVideoSiteIsJunk() {
        let a = Activity(appName: "Google Chrome", bundleID: "com.google.Chrome",
                         url: "https://www.douyin.com/video/123", title: "抖音")
        XCTAssertEqual(Classifier.junkReason(for: a, config: config), "douyin.com")
    }

    func testDomainMatchDoesNotHitLookalikeHosts() {
        let a = Activity(appName: "Safari", bundleID: "com.apple.Safari",
                         url: "https://www.box.com/files", title: "Box")
        XCTAssertNil(Classifier.junkReason(for: a, config: config))
    }

    func testPatternWithPathOnlyMatchesThatPath() {
        let shorts = Activity(appName: "Safari", bundleID: "com.apple.Safari",
                              url: "https://www.youtube.com/shorts/abc", title: nil)
        let lecture = Activity(appName: "Safari", bundleID: "com.apple.Safari",
                               url: "https://www.youtube.com/watch?v=abc", title: nil)
        XCTAssertNotNil(Classifier.junkReason(for: shorts, config: config))
        XCTAssertNil(Classifier.junkReason(for: lecture, config: config))
    }

    func testJunkAppMatchedByName() {
        let a = Activity(appName: "哔哩哔哩", bundleID: "tv.danmaku.bilianime", url: nil, title: nil)
        XCTAssertNotNil(Classifier.junkReason(for: a, config: config))
    }

    func testWorkAppIsNotJunk() {
        let a = Activity(appName: "Xcode", bundleID: "com.apple.dt.Xcode", url: nil, title: nil)
        XCTAssertNil(Classifier.junkReason(for: a, config: config))
    }
}

final class TrackerTests: XCTestCase {
    var config = Config()
    let cal = Calendar(identifier: .gregorian)

    func date(_ h: Int, _ m: Int = 0, day: Int = 19) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    /// 每 60 秒记录一次，持续 minutes 分钟，返回最后一次的决策。
    func run(_ t: inout Tracker, from start: Date, minutes: Int, junk: Bool = true) -> [Bool] {
        (1...minutes).map { i in
            t.record(isJunk: junk, isIdle: false, now: start.addingTimeInterval(Double(i) * 60),
                     elapsed: 60, config: config, calendar: cal) != nil
        }
    }

    func testNudgesOnceDaytimeLimitReached() {
        config.daytimeLimitMinutes = 20
        var t = Tracker()
        let nudges = run(&t, from: date(14), minutes: 20)
        XCTAssertEqual(nudges.filter { $0 }.count, 1)
        XCTAssertTrue(nudges.last!)
    }

    func testNightLimitIsShorter() {
        config.nightLimitMinutes = 5
        var t = Tracker()
        let nudges = run(&t, from: date(23, 30), minutes: 5)
        XCTAssertTrue(nudges.last!)
    }

    func testNightWindowWrapsPastMidnight() {
        XCTAssertTrue(config.isNight(date(1), calendar: cal))
        XCTAssertTrue(config.isNight(date(23), calendar: cal))
        XCTAssertFalse(config.isNight(date(12), calendar: cal))
    }

    func testRemindsAgainAfterSnoozeIfStillScrolling() {
        config.daytimeLimitMinutes = 10
        config.snoozeMinutes = 5
        var t = Tracker()
        let nudges = run(&t, from: date(14), minutes: 20)
        // 第 10、15、20 分钟各提醒一次
        XCTAssertEqual(nudges.enumerated().filter { $0.element }.map { $0.offset + 1 }, [10, 15, 20])
        XCTAssertEqual(t.nudgeCount, 3)
    }

    func testIdleTimeIsNotCounted() {
        var t = Tracker()
        _ = t.record(isJunk: true, isIdle: true, now: date(14), elapsed: 60, config: config, calendar: cal)
        XCTAssertEqual(t.todaySeconds, 0)
    }

    func testLongBreakResetsContinuousSession() {
        config.sessionBreakMinutes = 5
        var t = Tracker()
        _ = run(&t, from: date(14), minutes: 15)
        XCTAssertEqual(t.sessionSeconds, 15 * 60)
        // 中断 10 分钟后再刷，连续时长重新计算，今日累计保留
        _ = run(&t, from: date(14, 25), minutes: 1)
        XCTAssertEqual(t.sessionSeconds, 60)
        XCTAssertEqual(t.todaySeconds, 16 * 60)
    }

    func testNewDayResetsTodayTotal() {
        var t = Tracker()
        _ = run(&t, from: date(14), minutes: 3)
        _ = t.record(isJunk: false, isIdle: false, now: date(9, day: 20), elapsed: 60, config: config, calendar: cal)
        XCTAssertEqual(t.todaySeconds, 0)
    }

    func testAcceptingRestResetsSession() {
        config.daytimeLimitMinutes = 10
        var t = Tracker()
        _ = run(&t, from: date(14), minutes: 10)
        t.acceptRest()
        XCTAssertEqual(t.sessionSeconds, 0)
        XCTAssertEqual(t.nudgeCount, 0)
    }
}

final class MessagesTests: XCTestCase {
    func testNightMessageSuggestsSleep() {
        let n = Nudge(reason: "douyin.com", appName: "Safari", sessionMinutes: 12,
                      todayMinutes: 40, isNight: true, count: 1)
        XCTAssertTrue(Messages.make(for: n).body.contains("睡"))
    }
}
