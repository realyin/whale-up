import XCTest
@testable import WhaleUpCore

final class MascotBehaviorTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    let config = Config()

    func at(_ h: Int, _ m: Int, day: Int = 20) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    func run(_ b: inout MascotBehavior, _ now: Date, idle: Double = 0, junk: Bool = false) -> [MascotBehavior.Event] {
        b.update(now: now, idleSeconds: idle, isJunk: junk, config: config, calendar: cal, jitter: 0.5)
    }

    func testFallsAsleepWhenAwayAndWakesWithYawn() {
        var b = MascotBehavior()
        XCTAssertEqual(run(&b, at(14, 0), idle: 400), [.start(.sleep, line: nil)])
        XCTAssertEqual(run(&b, at(14, 1), idle: 460), [], "已经睡着了不重复")
        let wake = run(&b, at(14, 20), idle: 2)
        XCTAssertEqual(wake.first, .stop(.sleep))
        XCTAssertEqual(wake.last, .start(.yawn, line: "你回来啦～"))
    }

    func testEatsOnceAtEachMealtime() {
        var b = MascotBehavior()
        XCTAssertTrue(run(&b, at(11, 40)).isEmpty)
        let lunch = run(&b, at(11, 46))
        XCTAssertEqual(lunch, [.start(.eat, line: "到饭点啦，干饭去！🍚")])
        XCTAssertFalse(run(&b, at(11, 50)).contains { if case .start(.eat, _) = $0 { return true }; return false })
        XCTAssertEqual(run(&b, at(18, 5)).first, .start(.eat, line: "到饭点啦，干饭去！🍚"))
        XCTAssertTrue(run(&b, at(20, 0)).allSatisfy { if case .start(.eat, _) = $0 { return false }; return true }, "过了饭点一小时不吃")
        XCTAssertEqual(run(&b, at(11, 50, day: 21)).first, .start(.eat, line: "到饭点啦，干饭去！🍚"), "第二天还吃")
    }

    func testStretchesAfterLongContinuousUse() {
        var b = MascotBehavior()
        _ = run(&b, at(9, 0))
        XCTAssertFalse(run(&b, at(9, 30)).contains(.start(.stretch, line: "坐了好久啦，一起伸个懒腰～")))
        XCTAssertTrue(run(&b, at(9, 46)).contains(.start(.stretch, line: "坐了好久啦，一起伸个懒腰～")))
        XCTAssertFalse(run(&b, at(9, 50)).contains(.start(.stretch, line: "坐了好久啦，一起伸个懒腰～")))
        // 离开一阵再回来，重新计时
        _ = run(&b, at(10, 0), idle: 400)
        _ = run(&b, at(10, 10))
        XCTAssertFalse(run(&b, at(10, 40)).contains(.start(.stretch, line: "坐了好久啦，一起伸个懒腰～")))
    }

    func testYawnsMoreAtNightAndNotWhileWatchingJunk() {
        var day = MascotBehavior()
        _ = run(&day, at(14, 0))
        XCTAssertFalse(run(&day, at(14, 10)).contains { if case .start(.yawn, _) = $0 { return true }; return false })
        XCTAssertTrue(run(&day, at(14, 31)).contains { if case .start(.yawn, _) = $0 { return true }; return false })

        var night = MascotBehavior()
        _ = run(&night, at(23, 0))
        let yawns = run(&night, at(23, 12))
        XCTAssertTrue(yawns.contains(.start(.yawn, line: "好困……该睡了吧")))

        var junk = MascotBehavior()
        _ = run(&junk, at(14, 0), junk: true)
        XCTAssertTrue(run(&junk, at(15, 0), junk: true).allSatisfy { if case .start(.yawn, _) = $0 { return false }; return true })
    }
}
