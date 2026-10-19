import Foundation
import SQLite3

/// 一次观看：一个视频或一个网页，从打开到离开。由浏览器扩展上报，同一个 viewId 会多次上报以更新进度。
public struct ContentView: Codable, Equatable {
    public var viewId: String
    public var url: String
    public var title: String
    public var author: String?
    public var tags: [String]
    public var description: String?
    /// "video" 或 "page"
    public var kind: String
    public var browser: String
    /// Unix 时间（秒）
    public var startedAt: Double
    public var endedAt: Double
    /// 页面在前台、人在操作或视频在播的秒数
    public var activeSeconds: Double
    /// 视频实际播放的秒数
    public var watchedSeconds: Double
    /// 视频总长度（秒）
    public var mediaDuration: Double?

    public var site: String { Classifier.siteRule(from: url) ?? "" }

    public init(viewId: String, url: String, title: String, author: String? = nil, tags: [String] = [],
                description: String? = nil, kind: String = "page", browser: String = "chrome",
                startedAt: Double, endedAt: Double, activeSeconds: Double, watchedSeconds: Double = 0,
                mediaDuration: Double? = nil) {
        self.viewId = viewId
        self.url = url
        self.title = title
        self.author = author
        self.tags = tags
        self.description = description
        self.kind = kind
        self.browser = browser
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.watchedSeconds = watchedSeconds
        self.mediaDuration = mediaDuration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewId = try c.decode(String.self, forKey: .viewId)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "page"
        browser = try c.decodeIfPresent(String.self, forKey: .browser) ?? "chrome"
        startedAt = try c.decode(Double.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt) ?? startedAt
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        watchedSeconds = try c.decodeIfPresent(Double.self, forKey: .watchedSeconds) ?? 0
        mediaDuration = try c.decodeIfPresent(Double.self, forKey: .mediaDuration)
    }
}

/// 劝导弹窗上用户点的“为什么在刷”
public enum ReasonKind: String, Codable, CaseIterable {
    case tired, bored, avoiding, relaxing

    public var label: String {
        switch self {
        case .tired: return "😴 累了"
        case .bored: return "😐 无聊"
        case .avoiding: return "😣 在逃避某件事"
        case .relaxing: return "😌 就是想放松"
        }
    }
}

public struct NudgeReason: Equatable {
    public var at: Date
    public var reason: ReasonKind
    public var site: String
    public var sessionMinutes: Int

    public init(at: Date, reason: ReasonKind, site: String, sessionMinutes: Int) {
        self.at = at
        self.reason = reason
        self.site = site
        self.sessionMinutes = sessionMinutes
    }
}

public enum ContentStoreError: Error {
    case sqlite(String)
}

/// 本地内容数据库（SQLite），保存看过的内容和劝导时记录的原因。
public final class ContentStore {
    private var db: OpaquePointer?

    public static var defaultPath: String {
        Config.fileURL.deletingLastPathComponent().appendingPathComponent("content.sqlite").path
    }

    public init(path: String = ContentStore.defaultPath) throws {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw ContentStoreError.sqlite(lastError) }
        try exec("""
            CREATE TABLE IF NOT EXISTS views (
                view_id TEXT PRIMARY KEY,
                url TEXT NOT NULL, site TEXT NOT NULL, title TEXT NOT NULL,
                author TEXT, tags TEXT NOT NULL, description TEXT,
                kind TEXT NOT NULL, browser TEXT NOT NULL,
                started_at REAL NOT NULL, ended_at REAL NOT NULL,
                active_seconds REAL NOT NULL, watched_seconds REAL NOT NULL, media_duration REAL
            );
            CREATE INDEX IF NOT EXISTS views_started ON views(started_at);
            CREATE TABLE IF NOT EXISTS reasons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                at REAL NOT NULL, reason TEXT NOT NULL, site TEXT NOT NULL, session_minutes INTEGER NOT NULL
            );
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    /// 新增或更新一次观看；进度只增不减（防止迟到的旧上报覆盖新数据）
    public func upsert(_ v: ContentView) throws {
        let tags = String(data: try JSONEncoder().encode(v.tags), encoding: .utf8) ?? "[]"
        try run("""
            INSERT INTO views (view_id, url, site, title, author, tags, description, kind, browser,
                               started_at, ended_at, active_seconds, watched_seconds, media_duration)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(view_id) DO UPDATE SET
                url = excluded.url, site = excluded.site, title = excluded.title,
                author = COALESCE(excluded.author, author), tags = excluded.tags,
                description = COALESCE(excluded.description, description),
                kind = excluded.kind, media_duration = COALESCE(excluded.media_duration, media_duration),
                ended_at = MAX(ended_at, excluded.ended_at),
                active_seconds = MAX(active_seconds, excluded.active_seconds),
                watched_seconds = MAX(watched_seconds, excluded.watched_seconds)
            """, [v.viewId, v.url, v.site, v.title, v.author, tags, v.description, v.kind, v.browser,
                  v.startedAt, v.endedAt, v.activeSeconds, v.watchedSeconds, v.mediaDuration])
    }

    /// 时间范围内开始的观看，新的在前
    public func views(from: Date, to: Date) throws -> [ContentView] {
        try query("""
            SELECT view_id, url, title, author, tags, description, kind, browser,
                   started_at, ended_at, active_seconds, watched_seconds, media_duration
            FROM views WHERE started_at >= ? AND started_at < ? ORDER BY started_at DESC
            """, [from.timeIntervalSince1970, to.timeIntervalSince1970]) { s in
            let tagsJSON = Self.text(s, 4) ?? "[]"
            return ContentView(
                viewId: Self.text(s, 0)!, url: Self.text(s, 1)!, title: Self.text(s, 2)!,
                author: Self.text(s, 3),
                tags: (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? [],
                description: Self.text(s, 5), kind: Self.text(s, 6)!, browser: Self.text(s, 7)!,
                startedAt: sqlite3_column_double(s, 8), endedAt: sqlite3_column_double(s, 9),
                activeSeconds: sqlite3_column_double(s, 10), watchedSeconds: sqlite3_column_double(s, 11),
                mediaDuration: sqlite3_column_type(s, 12) == SQLITE_NULL ? nil : sqlite3_column_double(s, 12))
        }
    }

    public func addReason(_ r: NudgeReason) throws {
        try run("INSERT INTO reasons (at, reason, site, session_minutes) VALUES (?, ?, ?, ?)",
                [r.at.timeIntervalSince1970, r.reason.rawValue, r.site, r.sessionMinutes])
    }

    public func reasons(from: Date, to: Date) throws -> [NudgeReason] {
        try query("SELECT at, reason, site, session_minutes FROM reasons WHERE at >= ? AND at < ? ORDER BY at DESC",
                  [from.timeIntervalSince1970, to.timeIntervalSince1970]) { s in
            NudgeReason(at: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)),
                        reason: ReasonKind(rawValue: Self.text(s, 1)!) ?? .bored,
                        site: Self.text(s, 2)!, sessionMinutes: Int(sqlite3_column_int(s, 3)))
        }
    }

    public func prune(before date: Date) throws {
        try run("DELETE FROM views WHERE started_at < ?", [date.timeIntervalSince1970])
        try run("DELETE FROM reasons WHERE at < ?", [date.timeIntervalSince1970])
    }

    // MARK: - SQLite 小工具

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ContentStoreError.sqlite(lastError) }
    }

    private func prepare(_ sql: String, _ params: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw ContentStoreError.sqlite(lastError) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, transient)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            default: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ params: [Any?]) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw ContentStoreError.sqlite(lastError) }
    }

    private func query<T>(_ sql: String, _ params: [Any?], row: (OpaquePointer?) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(stmt)) }
        return out
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }
}
