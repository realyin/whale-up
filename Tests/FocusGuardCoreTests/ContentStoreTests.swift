import SQLite3
import XCTest
@testable import FocusGuardCore

final class ContentStoreTests: XCTestCase {
    var store: ContentStore!
    var path: String!

    override func setUpWithError() throws {
        path = NSTemporaryDirectory() + "fg-test-\(UUID().uuidString).sqlite"
        store = try ContentStore(path: path)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(atPath: path)
    }

    func view(_ id: String, at t: Double, active: Double = 30, watched: Double = 20, title: String = "视频") -> ContentView {
        ContentView(viewId: id, url: "https://www.bilibili.com/video/\(id)", title: title, author: "某UP主",
                    tags: ["搞笑", "日常"], description: "简介", kind: "video", browser: "chrome",
                    startedAt: t, endedAt: t + active, activeSeconds: active, watchedSeconds: watched,
                    mediaDuration: 60)
    }

    func testExtensionJSONDecodes() throws {
        let json = #"""
        {"viewId":"v1","url":"https://www.bilibili.com/video/BV1","title":"标题","author":"UP",
         "tags":["a"],"description":"d","kind":"video","browser":"chrome",
         "startedAt":1800000000,"endedAt":1800000030,"activeSeconds":30,"watchedSeconds":25,"mediaDuration":61.5}
        """#
        let v = try JSONDecoder().decode(ContentView.self, from: Data(json.utf8))
        XCTAssertEqual(v.site, "bilibili.com")
        XCTAssertEqual(v.mediaDuration, 61.5)
    }

    func testMissingOptionalFieldsDecode() throws {
        let json = #"{"viewId":"v1","url":"https://zhihu.com/q","title":"t","startedAt":1,"endedAt":2,"activeSeconds":1}"#
        let v = try JSONDecoder().decode(ContentView.self, from: Data(json.utf8))
        XCTAssertEqual(v.tags, [])
        XCTAssertNil(v.author)
        XCTAssertEqual(v.kind, "page")
    }

    func testUpsertKeepsOneRowPerViewAndLatestProgress() throws {
        try store.upsert(view("a", at: 1000, active: 10, watched: 8))
        try store.upsert(view("a", at: 1000, active: 40, watched: 35))
        try store.upsert(view("b", at: 2000))
        let rows = try store.views(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(rows.map(\.viewId), ["b", "a"])  // 新的在前
        XCTAssertEqual(rows.last?.activeSeconds, 40)
        XCTAssertEqual(rows.last?.tags, ["搞笑", "日常"])
        XCTAssertEqual(rows.last?.mediaDuration, 60)
        XCTAssertEqual(rows.last?.author, "某UP主")
    }

    func testProgressNeverGoesBackwards() throws {
        try store.upsert(view("a", at: 1000, active: 40, watched: 35))
        try store.upsert(view("a", at: 1000, active: 10, watched: 5))  // 迟到的旧心跳
        XCTAssertEqual(try store.views(from: .distantPast, to: .distantFuture).first?.activeSeconds, 40)
    }

    func testQueryByTimeRange() throws {
        try store.upsert(view("old", at: 1000))
        try store.upsert(view("new", at: 9000))
        let rows = try store.views(from: Date(timeIntervalSince1970: 5000), to: Date(timeIntervalSince1970: 10000))
        XCTAssertEqual(rows.map(\.viewId), ["new"])
    }

    func testDataSurvivesReopen() throws {
        try store.upsert(view("a", at: 1000))
        store = try ContentStore(path: path)
        XCTAssertEqual(try store.views(from: .distantPast, to: .distantFuture).count, 1)
    }

    func testBackgroundSecondsStoredAndDefaultsToZero() throws {
        var v = view("bg", at: 1000, active: 100, watched: 90)
        v.backgroundSeconds = 60
        try store.upsert(v)
        try store.upsert(view("fg", at: 2000))
        let rows = try store.views(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(rows.first { $0.viewId == "bg" }?.backgroundSeconds, 60)
        XCTAssertEqual(rows.first { $0.viewId == "fg" }?.backgroundSeconds, 0)
        let json = #"{"viewId":"x","url":"https://a.com","startedAt":1,"activeSeconds":1}"#
        XCTAssertEqual(try JSONDecoder().decode(ContentView.self, from: Data(json.utf8)).backgroundSeconds, 0)
    }

    func testOldDatabaseIsMigrated() throws {
        store = nil
        try FileManager.default.removeItem(atPath: path)
        // 第一版的表结构，没有 background_seconds 列
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE views (view_id TEXT PRIMARY KEY, url TEXT NOT NULL, site TEXT NOT NULL, title TEXT NOT NULL,
              author TEXT, tags TEXT NOT NULL, description TEXT, kind TEXT NOT NULL, browser TEXT NOT NULL,
              started_at REAL NOT NULL, ended_at REAL NOT NULL, active_seconds REAL NOT NULL,
              watched_seconds REAL NOT NULL, media_duration REAL);
            INSERT INTO views VALUES ('old','https://bilibili.com','bilibili.com','t',NULL,'[]',NULL,'video','chrome',1,2,1,1,NULL);
            """, nil, nil, nil)
        sqlite3_close(db)

        store = try ContentStore(path: path)
        var v = view("new", at: 3000)
        v.backgroundSeconds = 5
        try store.upsert(v)
        let rows = try store.views(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(rows.map(\.viewId), ["new", "old"])
        XCTAssertEqual(rows.first?.backgroundSeconds, 5)
    }

    func testLabelsAreStoredAndFoundByURL() throws {
        try store.upsert(view("a", at: 1000))
        try store.upsert(view("b", at: 2000))
        XCTAssertEqual(try store.unlabeledViews(limit: 10).map(\.viewId), ["b", "a"])

        let label = ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "r", model: "m")
        try store.setLabel(viewId: "a", label: label)
        XCTAssertEqual(try store.unlabeledViews(limit: 10).map(\.viewId), ["b"])
        XCTAssertEqual(try store.label(forURL: "https://www.bilibili.com/video/a"), label)
        XCTAssertNil(try store.label(forURL: "https://www.bilibili.com/video/b"))
        XCTAssertEqual(try store.views(from: .distantPast, to: .distantFuture).first { $0.viewId == "a" }?.label, label)
    }

    func testLatestLabelWinsForSameURL() throws {
        // 抖音信息流：同一个网址下先后看了两个视频
        var first = view("x1", at: 1000)
        first.url = "https://www.douyin.com/?recommend=1"
        var second = view("x2", at: 2000)
        second.url = first.url
        try store.upsert(first)
        try store.upsert(second)
        try store.setLabel(viewId: "x1", label: ContentLabel(isJunk: false, nutrition: 4, category: "学习", reason: "", model: "m"))
        try store.setLabel(viewId: "x2", label: ContentLabel(isJunk: true, nutrition: 1, category: "娱乐", reason: "", model: "m"))
        XCTAssertEqual(try store.label(forURL: first.url)?.category, "娱乐")
    }

    func testCachedLabelReusedForSameContent() throws {
        try store.upsert(view("a", at: 1000, title: "同一个视频"))
        try store.setLabel(viewId: "a", label: ContentLabel(isJunk: true, nutrition: 2, category: "娱乐", reason: "", model: "m"))
        let again = view("a2", at: 3000, title: "同一个视频")
        XCTAssertEqual(try store.cachedLabel(for: again)?.category, "娱乐")
        XCTAssertNil(try store.cachedLabel(for: view("c", at: 3000, title: "别的视频")))
    }

    func testFailedLabelingGivesUpAfterThreeAttempts() throws {
        try store.upsert(view("a", at: 1000))
        for _ in 0..<3 { try store.markLabelAttempt(viewId: "a") }
        XCTAssertTrue(try store.unlabeledViews(limit: 10).isEmpty)
    }

    func testReasonsAreStored() throws {
        try store.addReason(NudgeReason(at: Date(timeIntervalSince1970: 1000), reason: .tired, site: "bilibili.com", sessionMinutes: 20))
        let r = try store.reasons(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(r.first?.reason, .tired)
        XCTAssertEqual(r.first?.site, "bilibili.com")
    }

    func testPruneRemovesOldRows() throws {
        try store.upsert(view("old", at: 1000))
        try store.upsert(view("new", at: 9000))
        try store.prune(before: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(try store.views(from: .distantPast, to: .distantFuture).map(\.viewId), ["new"])
    }
}
