import XCTest
@testable import FocusGuardCore

final class FrictionTests: XCTestCase {
    func nudge(count: Int) -> Nudge {
        Nudge(reason: "douyin.com", appName: "Chrome", sessionMinutes: 20, todayMinutes: 30, isNight: false, count: count)
    }

    func testFrictionGrowsWithEachReminder() {
        let c = Config()
        XCTAssertEqual(Friction.level(for: nudge(count: 1), config: c), .none)
        XCTAssertEqual(Friction.level(for: nudge(count: 2), config: c), .wait(seconds: 10))
        XCTAssertEqual(Friction.level(for: nudge(count: 3), config: c), .writeReason(waitSeconds: 10))
        XCTAssertEqual(Friction.level(for: nudge(count: 5), config: c), .writeReason(waitSeconds: 10))
    }

    func testOverBudgetSkipsStraightToWriting() {
        var n = nudge(count: 1)
        n.overBudget = true
        XCTAssertEqual(Friction.level(for: n, config: Config()), .writeReason(waitSeconds: 10))
    }

    func testFrictionCanBeTurnedOff() {
        var c = Config()
        c.frictionEnabled = false
        XCTAssertEqual(Friction.level(for: nudge(count: 4), config: c), .none)
    }

    func testReasonMustBeMeaningful() {
        XCTAssertFalse(Friction.isAcceptableReason("  "))
        XCTAssertFalse(Friction.isAcceptableReason("嗯"))
        XCTAssertTrue(Friction.isAcceptableReason("想看完这一集"))
    }

    func testPauseOnlyWhenEnteringJunkAndNotTooOften() {
        var c = Config()
        c.pauseBeforeJunk = true
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(PauseGate.shouldPause(wasJunk: false, isJunk: true, lastPauseAt: nil, now: now, config: c))
        XCTAssertFalse(PauseGate.shouldPause(wasJunk: true, isJunk: true, lastPauseAt: nil, now: now, config: c), "已经在刷就不再拦")
        XCTAssertFalse(PauseGate.shouldPause(wasJunk: false, isJunk: false, lastPauseAt: nil, now: now, config: c))
        XCTAssertFalse(PauseGate.shouldPause(wasJunk: false, isJunk: true, lastPauseAt: now.addingTimeInterval(-300), now: now, config: c),
                       "10 分钟内最多一次")
        XCTAssertTrue(PauseGate.shouldPause(wasJunk: false, isJunk: true, lastPauseAt: now.addingTimeInterval(-700), now: now, config: c))
        c.pauseBeforeJunk = false
        XCTAssertFalse(PauseGate.shouldPause(wasJunk: false, isJunk: true, lastPauseAt: nil, now: now, config: c))
    }

    func testNudgeNoteIsStored() throws {
        let path = NSTemporaryDirectory() + "fg-friction-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try ContentStore(path: path)
        let id = try store.addNudge(NudgeRecord(at: Date(), site: "douyin.com", sessionMinutes: 20, isNight: false,
                                                byAI: false, title: "t", body: "b"))
        try store.setNudgeOutcome(id: id, outcome: .snoozed, note: "想看完这一集")
        let r = try store.nudges(from: .distantPast, to: .distantFuture).first
        XCTAssertEqual(r?.note, "想看完这一集")
        XCTAssertTrue(NudgeRecord.summary([r!])!.contains("想看完这一集"))
    }
}
