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
