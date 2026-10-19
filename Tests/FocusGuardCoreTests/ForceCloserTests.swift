import XCTest
@testable import FocusGuardCore

final class ForceCloserTests: XCTestCase {
    var config: Config = {
        var c = Config()
        c.forceCloseEnabled = true
        c.forceCloseMinutes = 10
        c.forceCloseCooldownMinutes = 10
        return c
    }()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// 每 30 秒记录一次，返回每次的动作
    func run(_ f: inout ForceCloser, fromMinute: Double, minutes: Double, onSite: Bool = true) -> [ForceAction?] {
        stride(from: 0.5, through: minutes, by: 0.5).map { m in
            f.record(onSite: onSite, isIdle: false, now: start.addingTimeInterval((fromMinute + m) * 60),
                     elapsed: 30, config: config)
        }
    }

    func testDisabledNeverActs() {
        config.forceCloseEnabled = false
        var f = ForceCloser()
        XCTAssertTrue(run(&f, fromMinute: 0, minutes: 30).allSatisfy { $0 == nil })
    }

    func testWarnsOneMinuteBeforeThenCloses() {
        var f = ForceCloser()
        let actions = run(&f, fromMinute: 0, minutes: 10)
        XCTAssertEqual(actions.compactMap { $0 }, [.warn, .close])
        XCTAssertEqual(actions[17], .warn)   // 第 9 分钟
        XCTAssertEqual(actions[19], .close)  // 第 10 分钟
    }

    func testReopeningDuringCooldownClosesImmediately() {
        var f = ForceCloser()
        _ = run(&f, fromMinute: 0, minutes: 10)
        // 关掉后 3 分钟又打开
        XCTAssertEqual(f.record(onSite: true, isIdle: false, now: start.addingTimeInterval(13 * 60),
                                elapsed: 30, config: config), .close)
        XCTAssertNotNil(f.blockedUntil)
    }

    func testAfterCooldownCountsFromZeroAgain() {
        var f = ForceCloser()
        _ = run(&f, fromMinute: 0, minutes: 10)
        let later = run(&f, fromMinute: 25, minutes: 5)
        XCTAssertTrue(later.allSatisfy { $0 == nil })
    }

    func testLeavingSiteForAWhileResetsTimer() {
        config.sessionBreakMinutes = 5
        var f = ForceCloser()
        _ = run(&f, fromMinute: 0, minutes: 8)
        // 离开 6 分钟后回来，重新计时，8 分钟内不会关
        let back = run(&f, fromMinute: 14, minutes: 8)
        XCTAssertTrue(back.allSatisfy { $0 != .close })
    }

    func testOffSiteDoesNotCount() {
        var f = ForceCloser()
        XCTAssertTrue(run(&f, fromMinute: 0, minutes: 30, onSite: false).allSatisfy { $0 == nil })
    }
}
