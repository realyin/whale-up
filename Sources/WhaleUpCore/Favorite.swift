import Foundation
import SQLite3

/// 用户收藏的一条内容，以及大模型提炼的要点
public struct Favorite: Equatable, Identifiable {
    public enum TextKind: String {
        /// 视频字幕
        case subtitle
        /// 网页正文
        case article
        /// 只有简介 / 标签
        case description
        /// 什么都没拿到，只有标题
        case none

        public var label: String {
            switch self {
            case .subtitle: return "字幕"
            case .article: return "正文"
            case .description: return "简介"
            case .none: return "标题"
            }
        }
    }

    public enum Status: String { case pending, done, failed }

    public var id: Int64 = 0
    public var url: String
    public var title: String
    public var author: String?
    public var text: String
    public var textKind: TextKind
    public var savedAt: Double
    public var status: Status = .pending
    public var points: KeyPoints?
    public var error: String?

    public var site: String { Classifier.siteRule(from: url) ?? "" }

    /// 不能收藏的原因：网站首页、列表页没有具体内容。nil 表示可以收藏
    public var rejectionReason: String? {
        guard let comps = URLComponents(string: url) else { return "这不是一个网页" }
        let rootPath = comps.path.isEmpty || comps.path == "/"
        // 抖音信息流 ?modal_id=7696… 这类带长 id 的参数说明在看具体内容
        let identifiesContent = (comps.queryItems ?? []).contains { ($0.value ?? "").count >= 6 }
        if rootPath && !identifiesContent { return "这是网站首页，没有具体内容。打开一篇文章或一个视频再收藏。" }
        return nil
    }

    public init(url: String, title: String, author: String? = nil, text: String, textKind: TextKind,
                savedAt: Double = Date().timeIntervalSince1970) {
        self.url = url
        self.title = title
        self.author = author
        self.text = text
        self.textKind = textKind
        self.savedAt = savedAt
    }
}

/// 一句话概括 + 3–5 个要点；不值得提炼时 worth 为 false
public struct KeyPoints: Codable, Equatable {
    public var worth: Bool
    public var summary: String
    public var points: [String]

    public init(summary: String, points: [String], worth: Bool = true) {
        self.worth = worth
        self.summary = summary
        self.points = points
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        worth = try c.decodeIfPresent(Bool.self, forKey: .worth) ?? true
        summary = try c.decode(String.self, forKey: .summary)
        points = try c.decodeIfPresent([String].self, forKey: .points) ?? []
    }

    public static let schema: [String: Any] = [
        "type": "object",
        "properties": ["worth": ["type": "boolean"], "summary": ["type": "string"],
                       "points": ["type": "array", "items": ["type": "string"]]],
        "required": ["worth", "summary", "points"],
        "additionalProperties": false,
    ]
    public static let example = #"{"worth": true, "summary": "用一个下载图片的例子讲清 async/await 怎样替代回调", "points": ["……", "……", "……"]}"#

    public static func parse(_ text: String) throws -> KeyPoints {
        var k = try LLMResponse.jsonObject(KeyPoints.self, from: text)
        k.points = k.worth ? Array(k.points.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5)) : []
        return k
    }

    public var markdown: String {
        "> \(summary)\n\n" + points.map { "- \($0)" }.joined(separator: "\n")
    }
}

public enum KeyPointsPrompt {
    static let maxChars = 15_000

    public static func make(for f: Favorite) -> (system: String, user: String) {
        let system = """
            用户收藏了一条网页或视频，想留下自己能带走的东西。请先判断，再提炼：
            - worth：这条内容有没有值得留下的知识、观点、方法或数据。网站首页、导航页、产品介绍、广告、纯娱乐，或者给出的信息太少（只有标题、一两句简介），都填 false。
            - summary：worth 为 true 时，一句话说清这条内容讲了什么，不超过 40 字；为 false 时，一句话说明为什么不值得提炼。
            - points：worth 为 true 时写 3–5 条，每条不超过 50 字，是读者能带走的具体观点、方法、数据或结论；为 false 时留空数组。
            不要介绍网站、平台或作者本身是什么；不要写“本文介绍了……”这类空话；不要编造给出内容里没有的细节。
            """
        var lines = ["网站：\(f.site)", "标题：\(f.title)"]
        if let a = f.author, !a.isEmpty { lines.append("作者：\(a)") }
        var text = f.text
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "\n（内容太长，只给出了前 \(maxChars) 字）" }
        if !text.isEmpty { lines.append("\(f.textKind.label)：\n\(text)") }
        return (system, lines.joined(separator: "\n"))
    }
}

/// 从网页 HTML 里取标题和正文（App 自己抓网页时用；扩展能直接读页面，不走这里）
public enum HTMLText {
    public static func extract(_ html: String) -> (title: String, text: String) {
        let title = decode(firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var body = html
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        if let article = firstMatch(#"<article\b[^>]*>([\s\S]*?)</article>"#, in: body) { body = article }
        else if let main = firstMatch(#"<main\b[^>]*>([\s\S]*?)</main>"#, in: body) { body = main }
        body = body.replacingOccurrences(of: #"<(br|/p|/div|/h\d|/li)\b[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let text = decode(body)
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t\u{00a0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return (title, text)
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func decode(_ s: String) -> String {
        var t = s
        for (k, v) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }
}

extension ContentStore {
    static let favoritesSchema = """
        CREATE TABLE IF NOT EXISTS favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, title TEXT NOT NULL, author TEXT,
            text TEXT NOT NULL, text_kind TEXT NOT NULL, saved_at REAL NOT NULL,
            status TEXT NOT NULL, points TEXT, error TEXT
        );
        """

    /// 收藏（同一网址只留一条；新拿到的正文更长时替换，并重新提取）
    @discardableResult
    public func saveFavorite(_ f: Favorite) throws -> Int64 {
        if let existing = try favorite(url: f.url) {
            if f.text.count > existing.text.count {
                try execute("""
                    UPDATE favorites SET title = ?, author = COALESCE(?, author), text = ?, text_kind = ?,
                    status = 'pending', points = NULL, error = NULL WHERE id = ?
                    """, [f.title, f.author, f.text, f.textKind.rawValue, Int(existing.id)])
            }
            return existing.id
        }
        return try insert("""
            INSERT INTO favorites (url, title, author, text, text_kind, saved_at, status) VALUES (?, ?, ?, ?, ?, ?, 'pending')
            """, [f.url, f.title, f.author, f.text, f.textKind.rawValue, f.savedAt])
    }

    public func setFavoriteResult(id: Int64, points: KeyPoints?, error: String?) throws {
        let json = points.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        try execute("UPDATE favorites SET status = ?, points = ?, error = ? WHERE id = ?",
                    [points != nil ? "done" : "failed", json, error, Int(id)])
    }

    /// 重新提取：标回待处理
    public func resetFavorite(id: Int64) throws {
        try execute("UPDATE favorites SET status = 'pending', error = NULL WHERE id = ?", [Int(id)])
    }

    public func deleteFavorite(id: Int64) throws {
        try execute("DELETE FROM favorites WHERE id = ?", [Int(id)])
    }

    /// 最新收藏的在前
    public func favorites() throws -> [Favorite] {
        try select("""
            SELECT id, url, title, author, text, text_kind, saved_at, status, points, error FROM favorites ORDER BY saved_at DESC
            """, [], row: Self.favoriteRow)
    }

    public func favorite(url: String) throws -> Favorite? {
        try select("""
            SELECT id, url, title, author, text, text_kind, saved_at, status, points, error FROM favorites WHERE url = ?
            """, [url], row: Self.favoriteRow).first
    }

    public func favoriteURLs() throws -> Set<String> {
        Set(try select("SELECT url FROM favorites", []) { Self.columnText($0, 0) ?? "" })
    }

    private static func favoriteRow(_ s: OpaquePointer?) -> Favorite {
        var f = Favorite(url: columnText(s, 1) ?? "", title: columnText(s, 2) ?? "", author: columnText(s, 3),
                         text: columnText(s, 4) ?? "", textKind: Favorite.TextKind(rawValue: columnText(s, 5) ?? "") ?? .none,
                         savedAt: sqlite3_column_double(s, 6))
        f.id = sqlite3_column_int64(s, 0)
        f.status = Favorite.Status(rawValue: columnText(s, 7) ?? "") ?? .pending
        f.points = columnText(s, 8).flatMap { try? JSONDecoder().decode(KeyPoints.self, from: Data($0.utf8)) }
        f.error = columnText(s, 9)
        return f
    }
}
