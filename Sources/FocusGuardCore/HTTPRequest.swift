import Foundation

/// 极简 HTTP 请求解析，只用于本机和浏览器扩展通信。
public struct HTTPRequest: Equatable {
    public var method: String
    public var path: String
    /// 键为小写
    public var headers: [String: String]
    public var body: Data

    public enum ParseResult: Equatable {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    public static func parse(_ data: Data) -> ParseResult {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count == 3, start[2].hasPrefix("HTTP/") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 4 * 1024 * 1024 else { return .invalid }
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .complete(HTTPRequest(method: String(start[0]), path: String(start[1]),
                                     headers: headers, body: Data(body.prefix(length))))
    }

    /// 只信任浏览器扩展（和本机程序）的请求：网页发出的跨域请求一定带自己的 Origin，伪造不了扩展的；
    /// 自定义请求头又会触发跨域预检（我们不响应预检），普通网页发不进来。
    /// 没有 Origin 的只可能是本机程序，它们本来就能直接读数据库，不必防。
    /// Host 必须是 127.0.0.1 / localhost，挡住把恶意域名解析到本机的“DNS 重绑定”攻击。
    public var isFromExtension: Bool {
        let host = (headers["host"] ?? "").split(separator: ":").first.map(String.init) ?? ""
        guard host == "127.0.0.1" || host == "localhost" else { return false }
        guard headers["x-focusguard"] == "1" else { return false }
        guard let origin = headers["origin"] else { return true }
        return origin.hasPrefix("chrome-extension://")
    }
}
