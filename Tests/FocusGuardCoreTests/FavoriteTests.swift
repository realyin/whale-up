import XCTest
@testable import FocusGuardCore

final class FavoriteTests: XCTestCase {
    var store: ContentStore!
    var path: String!

    override func setUpWithError() throws {
        path = NSTemporaryDirectory() + "fg-fav-\(UUID().uuidString).sqlite"
        store = try ContentStore(path: path)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(atPath: path)
    }

    func fav(_ url: String, text: String = "正文", kind: Favorite.TextKind = .article) -> Favorite {
        Favorite(url: url, title: "标题", author: "作者", text: text, textKind: kind)
    }

    func testSaveListAndResult() throws {
        let id = try store.saveFavorite(fav("https://www.ruanyifeng.com/blog/1.html"))
        XCTAssertEqual(try store.favorites().first?.status, .pending)
        XCTAssertEqual(try store.favorites().first?.site, "ruanyifeng.com")
        let points = KeyPoints(summary: "一句话", points: ["要点一", "要点二", "要点三"])
        try store.setFavoriteResult(id: id, points: points, error: nil)
        let f = try store.favorites().first
        XCTAssertEqual(f?.status, .done)
        XCTAssertEqual(f?.points, points)
        XCTAssertTrue(try store.favoriteURLs().contains("https://www.ruanyifeng.com/blog/1.html"))
    }

    func testSavingSameURLAgainKeepsOneAndPrefersLongerText() throws {
        let a = try store.saveFavorite(fav("https://x.com/a", text: "短", kind: .description))
        let b = try store.saveFavorite(fav("https://x.com/a", text: "这是一段更长的字幕文本", kind: .subtitle))
        XCTAssertEqual(a, b)
        let f = try store.favorites()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.first?.textKind, .subtitle)
        XCTAssertEqual(f.first?.status, .pending, "正文变了，要重新提取")
        _ = try store.saveFavorite(fav("https://x.com/a", text: "短", kind: .description))
        XCTAssertEqual(try store.favorites().first?.textKind, .subtitle, "不会被更短的覆盖")
    }

    func testFailureAndDelete() throws {
        let id = try store.saveFavorite(fav("https://x.com/b"))
        try store.setFavoriteResult(id: id, points: nil, error: "超时")
        XCTAssertEqual(try store.favorites().first?.status, .failed)
        XCTAssertEqual(try store.favorites().first?.error, "超时")
        try store.deleteFavorite(id: id)
        XCTAssertTrue(try store.favorites().isEmpty)
    }

    func testKeyPointsPromptAndParse() throws {
        let long = String(repeating: "字", count: 30_000)
        let p = KeyPointsPrompt.make(for: fav("https://www.bilibili.com/video/BV1", text: long, kind: .subtitle))
        XCTAssertTrue(p.user.contains("字幕"))
        XCTAssertLessThan(p.user.count, 17_000, "过长的正文要截断")
        XCTAssertTrue(p.system.contains("3–5"))
        let parsed = try KeyPoints.parse(#"{"summary":"s","points":["1","2","3","4","5","6"]}"#)
        XCTAssertEqual(parsed.points.count, 5)
        XCTAssertEqual((KeyPoints.schema["required"] as! [String]).sorted(), ["points", "summary"])
    }

    func testHTMLTextPrefersArticleAndDropsScripts() {
        let html = """
            <html><head><title>好文章 &amp; 标题</title><script>var x = 1;</script><style>p{}</style></head>
            <body><nav>导航 首页</nav><article><h1>好文章</h1><p>第一段&nbsp;内容。</p><p>第二段 &lt;重点&gt;</p></article>
            <footer>版权所有</footer></body></html>
            """
        let r = HTMLText.extract(html)
        XCTAssertEqual(r.title, "好文章 & 标题")
        XCTAssertTrue(r.text.contains("第一段 内容。"))
        XCTAssertTrue(r.text.contains("第二段 <重点>"))
        XCTAssertFalse(r.text.contains("var x"))
        XCTAssertFalse(r.text.contains("导航"))
        XCTAssertFalse(r.text.contains("版权所有"))
    }
}
