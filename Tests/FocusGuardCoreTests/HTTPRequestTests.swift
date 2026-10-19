import XCTest
@testable import FocusGuardCore

final class HTTPRequestTests: XCTestCase {
    func raw(_ s: String) -> Data { Data(s.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

    func testParsesCompletePost() {
        let body = #"{"a":1}"#
        let data = raw("POST /views HTTP/1.1\nHost: 127.0.0.1\nContent-Length: \(body.utf8.count)\nX-FocusGuard: 1\n\n") + Data(body.utf8)
        guard case .complete(let r) = HTTPRequest.parse(data) else { return XCTFail() }
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/views")
        XCTAssertEqual(r.headers["x-focusguard"], "1")
        XCTAssertEqual(String(data: r.body, encoding: .utf8), body)
    }

    func testWaitsForRestOfBody() {
        let data = raw("POST /views HTTP/1.1\nContent-Length: 10\n\n") + Data("12345".utf8)
        XCTAssertEqual(HTTPRequest.parse(data), .incomplete)
    }

    func testWaitsForHeaders() {
        XCTAssertEqual(HTTPRequest.parse(Data("GET /status HT".utf8)), .incomplete)
    }

    func testGetWithoutBody() {
        guard case .complete(let r) = HTTPRequest.parse(raw("GET /status HTTP/1.1\nHost: x\n\n")) else { return XCTFail() }
        XCTAssertEqual(r.path, "/status")
        XCTAssertTrue(r.body.isEmpty)
    }

    func testGarbageIsInvalid() {
        XCTAssertEqual(HTTPRequest.parse(raw("hello\n\n")), .invalid)
    }

    func testOnlyExtensionRequestsAreTrusted() {
        var r = HTTPRequest(method: "POST", path: "/views", headers: ["host": "127.0.0.1:47621", "x-focusguard": "1", "origin": "chrome-extension://abc"], body: Data())
        XCTAssertTrue(r.isFromExtension)
        r.headers["origin"] = "https://evil.example"
        XCTAssertFalse(r.isFromExtension)
        r.headers = ["host": "127.0.0.1:47621", "origin": "chrome-extension://abc"]
        XCTAssertFalse(r.isFromExtension)
        r.headers = ["host": "127.0.0.1:47621", "x-focusguard": "1"]  // 本机程序（如 curl）
        XCTAssertTrue(r.isFromExtension)
        r.headers = ["host": "127.0.0.1:47621", "x-focusguard": "1", "origin": "safari-web-extension://ABC-123"]
        XCTAssertTrue(r.isFromExtension, "Safari 扩展")
        r.headers = ["host": "evil.example:47621", "x-focusguard": "1"]  // DNS 重绑定
        XCTAssertFalse(r.isFromExtension)
    }
}
