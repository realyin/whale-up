import XCTest
@testable import FocusGuardCore

final class WeeklyTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func date(_ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!
    }

    func testWeekKeyAndRange() {
        // 2026-10-20 是周二，属于第 43 周（10-19 周一 ~ 10-25 周日）
        let w = Week(containing: date(20), calendar: cal)
        XCTAssertEqual(w.key, "2026-W43")
        XCTAssertEqual(cal.component(.day, from: w.start), 19)
        XCTAssertEqual(w.days.count, 7)
        XCTAssertEqual(Week(containing: date(26), calendar: cal).previous(calendar: cal).key, "2026-W43")
    }

    func testWeeklyPromptAggregatesTheWeek() {
        var config = Config()
        config.llm.enabled = true
        var fun = ContentView(viewId: "1", url: "https://www.douyin.com/", title: "沙雕合集", kind: "video",
                              startedAt: date(20, 23).timeIntervalSince1970, endedAt: 0, activeSeconds: 3600)
        fun.label = ContentLabel(isJunk: true, nutrition: 1, category: "搞笑", reason: "", model: "m", hook: "搞笑")
        var learn = ContentView(viewId: "2", url: "https://www.bilibili.com/video/x", title: "Swift 并发入门", kind: "video",
                                startedAt: date(21, 20).timeIntervalSince1970, endedAt: 0, activeSeconds: 1200)
        learn.label = ContentLabel(isJunk: false, nutrition: 5, category: "技术", reason: "", model: "m")
        let days = [
            WeekDay(day: date(20), views: [fun], reasons: [.tired, .tired], nudges: [], digest: "周二深夜刷了一小时搞笑视频"),
            WeekDay(day: date(21), views: [learn], reasons: [], nudges: [], digest: nil),
        ]
        let p = WeeklyPrompt.make(week: Week(containing: date(20), calendar: cal), days: days, config: config, calendar: cal)
        XCTAssertTrue(p.user.contains("2026-W43"))
        XCTAssertTrue(p.user.contains("没营养共 1 小时 0 分钟"), p.user)
        XCTAssertTrue(p.user.contains("搞笑"))
        XCTAssertTrue(p.user.contains("😴 累了×2"))
        XCTAssertTrue(p.user.contains("周二深夜刷了一小时搞笑视频"))
        XCTAssertTrue(p.user.contains("Swift 并发入门"))
        XCTAssertTrue(p.system.contains("需要加强"))
    }

    func testObsidianNoteHasFrontmatter() {
        let note = ObsidianNote.render(title: "2026-W43 专注复盘", kind: "每周复盘", date: "2026-10-26", body: "## 本周概况\n不错")
        XCTAssertTrue(note.hasPrefix("---\n"))
        XCTAssertTrue(note.contains("tags: [专注守护, 每周复盘]"))
        XCTAssertTrue(note.contains("# 2026-W43 专注复盘"))
        XCTAssertTrue(note.contains("## 本周概况"))
    }

    func testDetectsOpenVaultFromObsidianConfig() {
        let json = #"{"vaults":{"a":{"path":"/vaults/Wiki","ts":1},"b":{"path":"/vaults/Main","ts":2,"open":true}}}"#
        XCTAssertEqual(ObsidianNote.openVault(fromConfig: Data(json.utf8)), "/vaults/Main")
        let none = #"{"vaults":{"a":{"path":"/vaults/Wiki","ts":1}}}"#
        XCTAssertEqual(ObsidianNote.openVault(fromConfig: Data(none.utf8)), "/vaults/Wiki")
        XCTAssertNil(ObsidianNote.openVault(fromConfig: Data("{}".utf8)))
    }
}
