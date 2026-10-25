import Foundation
import SQLite3

/// 鲸醒自己的记录：强制关闭关了 / 没关、为什么，退回视频、出错、改设置。
/// 给“问问大肥鱼”查问题用（“这个视频为什么没关？”“刚才报的什么错？”）。只存在本机
public struct AppEvent: Equatable {
    public enum Kind: String, CaseIterable {
        /// 对当前网页的判断有变化：会不会被强制关闭、为什么
        case decision
        /// 真的做了的事：关网页、退回视频、弹劝导
        case action
        /// 出错：大模型判断失败、浏览器脚本失败等
        case error
        /// 设置改动：名单、今天多看少看、暂停
        case setting
    }

    public var at: Date
    public var kind: Kind
    public var site: String
    public var url: String
    public var title: String
    public var detail: String

    public init(at: Date = Date(), kind: Kind, site: String = "", url: String = "", title: String = "", detail: String) {
        self.at = at
        self.kind = kind
        self.site = site
        self.url = url
        self.title = title
        self.detail = detail
    }
}

extension ContentStore {
    static let eventsSchema = """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, kind TEXT NOT NULL,
            site TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS events_at ON events(at);
        """

    public func addEvent(_ e: AppEvent) throws {
        try execute("INSERT INTO events (at, kind, site, url, title, detail) VALUES (?, ?, ?, ?, ?, ?)",
                    [e.at.timeIntervalSince1970, e.kind.rawValue, e.site, e.url, e.title, e.detail])
    }

    /// 时间范围内的记录，新的在前。kind、site 为空不筛；keyword 在网址、标题、说明里找
    public func events(from: Date, to: Date, kind: AppEvent.Kind? = nil, site: String? = nil,
                       keyword: String? = nil, limit: Int = 50) throws -> [AppEvent] {
        var sql = "SELECT at, kind, site, url, title, detail FROM events WHERE at >= ? AND at < ?"
        var params: [Any?] = [from.timeIntervalSince1970, to.timeIntervalSince1970]
        if let kind { sql += " AND kind = ?"; params.append(kind.rawValue) }
        if let site, !site.isEmpty { sql += " AND (site = ? OR site LIKE ?)"; params += [site, "%.\(site)"] }
        if let keyword, !keyword.isEmpty {
            sql += " AND (url LIKE ? OR title LIKE ? OR detail LIKE ?)"
            params += Array(repeating: "%\(keyword)%", count: 3)
        }
        sql += " ORDER BY at DESC, id DESC LIMIT ?"
        params.append(limit)
        return try select(sql, params) { s in
            AppEvent(at: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)),
                     kind: AppEvent.Kind(rawValue: Self.columnText(s, 1) ?? "") ?? .action,
                     site: Self.columnText(s, 2) ?? "", url: Self.columnText(s, 3) ?? "",
                     title: Self.columnText(s, 4) ?? "", detail: Self.columnText(s, 5) ?? "")
        }
    }

    /// 最早的一条记录是什么时候（这之前没有记录，不能用“记录里没有”下结论）
    public func firstEventDate() throws -> Date? {
        try select("SELECT MIN(at) FROM events", []) { s in
            sqlite3_column_type(s, 0) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 0))
        }.first ?? nil
    }

    /// 改正大模型对某个网址的判断（这个网址所有的观看记录都改）
    public func setLabel(forURL url: String, label: ContentLabel) throws {
        let json = String(data: try JSONEncoder().encode(label), encoding: .utf8)
        try execute("UPDATE views SET label = ? WHERE url = ?", [json, url])
    }

    /// 网址或标题里含关键字的观看，新的在前
    public func views(matching keyword: String, from: Date, to: Date, limit: Int = 20) throws -> [ContentView] {
        try select("""
            SELECT \(Self.viewColumns) FROM views
            WHERE started_at >= ? AND started_at < ? AND (url LIKE ? OR title LIKE ? OR IFNULL(author, '') LIKE ?)
            ORDER BY started_at DESC LIMIT ?
            """, [from.timeIntervalSince1970, to.timeIntervalSince1970, "%\(keyword)%", "%\(keyword)%", "%\(keyword)%", limit],
            row: Self.viewRow)
    }
}
