import XCTest
@testable import WhaleUpCore

final class PageKindTests: XCTestCase {
    func testBrowsePages() {
        for url in ["https://www.bilibili.com/", "https://m.bilibili.com", "https://search.bilibili.com/all?keyword=swift",
                    "https://space.bilibili.com/123", "https://www.youtube.com/", "https://m.youtube.com/results?search_query=swift",
                    "https://www.youtube.com/@channel", "https://www.douyin.com/search/猫", "https://www.xiaohongshu.com/explore"] {
            XCTAssertTrue(PageKind.isBrowsePage(url), url)
        }
    }

    func testContentPages() {
        for url in ["https://www.bilibili.com/video/BV1xx411c7mD", "https://m.bilibili.com/video/BV1xx",
                    "https://www.youtube.com/watch?v=abc", "https://m.youtube.com/shorts/abc",
                    "https://www.douyin.com/", "https://www.douyin.com/video/123", "https://www.tiktok.com/",
                    "https://www.xiaohongshu.com/explore/65abc", "https://weibo.com/"] {
            XCTAssertFalse(PageKind.isBrowsePage(url), url)
        }
    }
}
