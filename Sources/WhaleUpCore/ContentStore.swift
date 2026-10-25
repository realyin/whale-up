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
    /// 计入的总秒数：页面在前台且人在操作，或视频在播放（含后台播放）
    public var activeSeconds: Double
    /// 视频实际播放的秒数
    public var watchedSeconds: Double
    /// 其中标签页在后台 / 窗口最小化或被挡住时播放的秒数（“放着听”）
    public var backgroundSeconds: Double
    /// 视频总长度（秒）
    public var mediaDuration: Double?
    /// 大模型的判断（App 生成，扩展不上报）
    public var label: ContentLabel?

    public var site: String { Classifier.siteRule(from: url) ?? "" }

    public init(viewId: String, url: String, title: String, author: String? = nil, tags: [String] = [],
                description: String? = nil, kind: String = "page", browser: String = "chrome",
                startedAt: Double, endedAt: Double, activeSeconds: Double, watchedSeconds: Double = 0,
                backgroundSeconds: Double = 0, mediaDuration: Double? = nil) {
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
        self.backgroundSeconds = backgroundSeconds
        self.mediaDuration = mediaDuration
    }

    private enum CodingKeys: String, CodingKey {
        case viewId, url, title, author, tags, description, kind, browser, startedAt, endedAt
        case activeSeconds, watchedSeconds, backgroundSeconds, mediaDuration
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
        backgroundSeconds = try c.decodeIfPresent(Double.self, forKey: .backgroundSeconds) ?? 0
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
                active_seconds REAL NOT NULL, watched_seconds REAL NOT NULL, media_duration REAL,
                background_seconds REAL NOT NULL DEFAULT 0,
                label TEXT, label_attempts INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS views_started ON views(started_at);
            CREATE TABLE IF NOT EXISTS reasons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                at REAL NOT NULL, reason TEXT NOT NULL, site TEXT NOT NULL, session_minutes INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS nudges (
                id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, site TEXT NOT NULL,
                session_minutes INTEGER NOT NULL, is_night INTEGER NOT NULL, by_ai INTEGER NOT NULL,
                title TEXT NOT NULL, body TEXT NOT NULL, outcome TEXT, note TEXT
            );
            CREATE TABLE IF NOT EXISTS digests (
                day TEXT PRIMARY KEY, text TEXT NOT NULL, model TEXT NOT NULL, created_at REAL NOT NULL
            );
            """)
        try exec(Self.favoritesSchema)
        // 升级旧数据库：补上后来加的列
        let columns = try query("PRAGMA table_info(views)", []) { Self.text($0, 1) ?? "" }
        for (name, type) in [("background_seconds", "REAL NOT NULL DEFAULT 0"), ("label", "TEXT"),
                             ("label_attempts", "INTEGER NOT NULL DEFAULT 0")] where !columns.contains(name) {
            try exec("ALTER TABLE views ADD COLUMN \(name) \(type)")
        }
        try exec("CREATE INDEX IF NOT EXISTS views_url ON views(url)")
        let nudgeColumns = try query("PRAGMA table_info(nudges)", []) { Self.text($0, 1) ?? "" }
        if !nudgeColumns.contains("note") { try exec("ALTER TABLE nudges ADD COLUMN note TEXT") }
    }

    deinit {
        sqlite3_close(db)
    }

    /// 新增或更新一次观看；进度只增不减（防止迟到的旧上报覆盖新数据）
    public func upsert(_ v: ContentView) throws {
        let tags = String(data: try JSONEncoder().encode(v.tags), encoding: .utf8) ?? "[]"
        try run("""
            INSERT INTO views (view_id, url, site, title, author, tags, description, kind, browser,
                               started_at, ended_at, active_seconds, watched_seconds, media_duration,
                               background_seconds)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(view_id) DO UPDATE SET
                url = excluded.url, site = excluded.site, title = excluded.title,
                author = COALESCE(excluded.author, author), tags = excluded.tags,
                description = COALESCE(excluded.description, description),
                kind = excluded.kind, media_duration = COALESCE(excluded.media_duration, media_duration),
                ended_at = MAX(ended_at, excluded.ended_at),
                active_seconds = MAX(active_seconds, excluded.active_seconds),
                watched_seconds = MAX(watched_seconds, excluded.watched_seconds),
                background_seconds = MAX(background_seconds, excluded.background_seconds)
            """, [v.viewId, v.url, v.site, v.title, v.author, tags, v.description, v.kind, v.browser,
                  v.startedAt, v.endedAt, v.activeSeconds, v.watchedSeconds, v.mediaDuration,
                  v.backgroundSeconds])
    }

    /// 时间范围内开始的观看，新的在前
    public func views(from: Date, to: Date) throws -> [ContentView] {
        try query("""
            SELECT \(Self.viewColumns) FROM views
            WHERE started_at >= ? AND started_at < ? ORDER BY started_at DESC
            """, [from.timeIntervalSince1970, to.timeIntervalSince1970], row: Self.viewRow)
    }

    private static func viewRow(_ s: OpaquePointer?) -> ContentView {
        let tagsJSON = text(s, 4) ?? "[]"
        return ContentView(
            viewId: text(s, 0)!, url: text(s, 1)!, title: text(s, 2)!,
            author: text(s, 3),
            tags: (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? [],
            description: text(s, 5), kind: text(s, 6)!, browser: text(s, 7)!,
            startedAt: sqlite3_column_double(s, 8), endedAt: sqlite3_column_double(s, 9),
            activeSeconds: sqlite3_column_double(s, 10), watchedSeconds: sqlite3_column_double(s, 11),
            backgroundSeconds: sqlite3_column_double(s, 13),
            mediaDuration: sqlite3_column_type(s, 12) == SQLITE_NULL ? nil : sqlite3_column_double(s, 12))
            .with(label: decodeLabel(text(s, 14)))
    }

    private static let viewColumns = """
        view_id, url, title, author, tags, description, kind, browser,
        started_at, ended_at, active_seconds, watched_seconds, media_duration, background_seconds, label
        """

    // MARK: - 大模型判断

    /// 还没判断过、有标题、停留了一会儿、失败不到 3 次的观看，新的在前
    public func unlabeledViews(limit: Int) throws -> [ContentView] {
        try query("""
            SELECT \(Self.viewColumns) FROM views
            WHERE label IS NULL AND title != '' AND active_seconds >= 5 AND label_attempts < 3
            ORDER BY started_at DESC LIMIT ?
            """, [limit], row: Self.viewRow)
    }

    public func setLabel(viewId: String, label: ContentLabel) throws {
        let json = String(data: try JSONEncoder().encode(label), encoding: .utf8)
        try run("UPDATE views SET label = ? WHERE view_id = ?", [json, viewId])
    }

    public func markLabelAttempt(viewId: String) throws {
        try run("UPDATE views SET label_attempts = label_attempts + 1 WHERE view_id = ?", [viewId])
    }

    /// 这个网址最近一次的判断（抖音信息流网址不变，取最新看的那个视频）
    public func label(forURL url: String) throws -> ContentLabel? {
        try query("SELECT label FROM views WHERE url = ? AND label IS NOT NULL ORDER BY started_at DESC LIMIT 1",
                  [url]) { Self.decodeLabel(Self.text($0, 0)) }.first ?? nil
    }

    /// 这个网址上放的视频的判断（只看扩展报上来是视频的记录）：给“只拦视频”用
    public func videoLabel(forURL url: String) throws -> ContentLabel? {
        try query("SELECT label FROM views WHERE url = ? AND kind = 'video' AND label IS NOT NULL ORDER BY started_at DESC LIMIT 1",
                  [url]) { Self.decodeLabel(Self.text($0, 0)) }.first ?? nil
    }

    /// 同一条内容（网站 + 标题 + 作者相同）以前判断过，就直接复用，不再调用大模型
    public func cachedLabel(for v: ContentView) throws -> ContentLabel? {
        try query("""
            SELECT label FROM views WHERE site = ? AND title = ? AND IFNULL(author, '') = ? AND label IS NOT NULL
            ORDER BY started_at DESC LIMIT 1
            """, [v.site, v.title, v.author ?? ""]) { Self.decodeLabel(Self.text($0, 0)) }.first ?? nil
    }

    private static func decodeLabel(_ json: String?) -> ContentLabel? {
        json.flatMap { try? JSONDecoder().decode(ContentLabel.self, from: Data($0.utf8)) }
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

    // MARK: - 每日小结

    public func saveDigest(_ d: Digest) throws {
        try run("INSERT OR REPLACE INTO digests (day, text, model, created_at) VALUES (?, ?, ?, ?)",
                [d.day, d.text, d.model, d.createdAt])
    }

    /// 所有小结和周复盘，最近写的在前
    public func allDigests() throws -> [Digest] {
        try query("SELECT day, text, model, created_at FROM digests ORDER BY created_at DESC", []) { s in
            Digest(day: Self.text(s, 0)!, text: Self.text(s, 1)!, model: Self.text(s, 2)!,
                   createdAt: sqlite3_column_double(s, 3))
        }
    }

    public func digest(day: String) throws -> Digest? {
        try query("SELECT day, text, model, created_at FROM digests WHERE day = ?", [day]) { s in
            Digest(day: Self.text(s, 0)!, text: Self.text(s, 1)!, model: Self.text(s, 2)!,
                   createdAt: sqlite3_column_double(s, 3))
        }.first
    }

    // MARK: - 删除

    /// 删除某一天的全部记录：看过的内容、原因、劝导、小结
    public func deleteDay(from: Date, to: Date, dayKey: String) throws {
        let range: [Any?] = [from.timeIntervalSince1970, to.timeIntervalSince1970]
        try run("DELETE FROM views WHERE started_at >= ? AND started_at < ?", range)
        try run("DELETE FROM reasons WHERE at >= ? AND at < ?", range)
        try run("DELETE FROM nudges WHERE at >= ? AND at < ?", range)
        try run("DELETE FROM digests WHERE day = ?", [dayKey])
    }

    /// 删除某个网站的全部观看记录
    public func deleteSite(_ site: String) throws {
        try run("DELETE FROM views WHERE site = ?", [site])
    }

    public func prune(before date: Date) throws {
        try run("DELETE FROM views WHERE started_at < ?", [date.timeIntervalSince1970])
        try run("DELETE FROM reasons WHERE at < ?", [date.timeIntervalSince1970])
        try run("DELETE FROM nudges WHERE at < ?", [date.timeIntervalSince1970])
    }

    // MARK: - SQLite 小工具

    /// 供扩展里的其他表使用
    func insert(_ sql: String, _ params: [Any?]) throws -> Int64 {
        try run(sql, params)
        return sqlite3_last_insert_rowid(db)
    }

    func execute(_ sql: String, _ params: [Any?]) throws {
        try run(sql, params)
    }

    func select<T>(_ sql: String, _ params: [Any?], row: (OpaquePointer?) -> T) throws -> [T] {
        try query(sql, params, row: row)
    }

    static func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        text(stmt, col)
    }

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

extension ContentView {
    func with(label: ContentLabel?) -> ContentView {
        var copy = self
        copy.label = label
        return copy
    }
}

/// 一次劝导弹窗以及用户的反应
public struct NudgeRecord: Equatable {
    public enum Outcome: String {
        /// 点了“关掉它”
        case accepted
        /// 点了“再刷一会儿”
        case snoozed
    }

    public var id: Int64 = 0
    public var at: Date
    public var site: String
    public var sessionMinutes: Int
    public var isNight: Bool
    public var byAI: Bool
    public var title: String
    public var body: String
    public var outcome: Outcome?
    /// 想继续刷时写下的理由
    public var note: String?

    public init(at: Date, site: String, sessionMinutes: Int, isNight: Bool, byAI: Bool, title: String, body: String,
                outcome: Outcome? = nil) {
        self.at = at
        self.site = site
        self.sessionMinutes = sessionMinutes
        self.isNight = isNight
        self.byAI = byAI
        self.title = title
        self.body = body
        self.outcome = outcome
    }

    /// 给大模型看的劝导效果总结：接受率 + 有效 / 无效的说法各举几例
    public static func summary(_ records: [NudgeRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        let accepted = records.filter { $0.outcome == .accepted }
        let snoozed = records.filter { $0.outcome == .snoozed }
        var text = "提醒 \(records.count) 次，接受 \(accepted.count) 次，再刷 \(snoozed.count) 次"
        let ignored = records.count - accepted.count - snoozed.count
        if ignored > 0 { text += "，没理会 \(ignored) 次" }
        text += "。"
        if !accepted.isEmpty {
            text += "让他停下来的说法：" + accepted.suffix(3).map { "「\($0.body)」" }.joined(separator: "、") + "。"
        }
        let notes = records.compactMap(\.note).filter { !$0.isEmpty }
        if !notes.isEmpty {
            text += "他坚持要继续时写的理由：" + notes.suffix(5).map { "「\($0)」" }.joined(separator: "、") + "。"
        }
        if !snoozed.isEmpty {
            text += "没用的说法：" + snoozed.suffix(3).map { "「\($0.body)」" }.joined(separator: "、") + "。"
        }
        return text
    }
}

extension ContentStore {
    @discardableResult
    public func addNudge(_ r: NudgeRecord) throws -> Int64 {
        try insert("""
            INSERT INTO nudges (at, site, session_minutes, is_night, by_ai, title, body, outcome)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [r.at.timeIntervalSince1970, r.site, r.sessionMinutes, r.isNight ? 1 : 0, r.byAI ? 1 : 0,
                  r.title, r.body, r.outcome?.rawValue])
    }

    public func setNudgeOutcome(id: Int64, outcome: NudgeRecord.Outcome, note: String? = nil) throws {
        try execute("UPDATE nudges SET outcome = ?, note = ? WHERE id = ?", [outcome.rawValue, note, Int(id)])
    }

    public func nudges(from: Date, to: Date) throws -> [NudgeRecord] {
        try select("""
            SELECT id, at, site, session_minutes, is_night, by_ai, title, body, outcome, note
            FROM nudges WHERE at >= ? AND at < ? ORDER BY at
            """, [from.timeIntervalSince1970, to.timeIntervalSince1970]) { s in
            var r = NudgeRecord(at: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                                site: Self.columnText(s, 2) ?? "", sessionMinutes: Int(sqlite3_column_int(s, 3)),
                                isNight: sqlite3_column_int(s, 4) != 0, byAI: sqlite3_column_int(s, 5) != 0,
                                title: Self.columnText(s, 6) ?? "", body: Self.columnText(s, 7) ?? "",
                                outcome: Self.columnText(s, 8).flatMap(NudgeRecord.Outcome.init(rawValue:)))
            r.id = sqlite3_column_int64(s, 0)
            r.note = Self.columnText(s, 9)
            return r
        }
    }
}
