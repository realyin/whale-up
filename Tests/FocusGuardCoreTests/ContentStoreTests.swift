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
