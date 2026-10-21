import Foundation
import FocusGuardCore

/// 用“写报告用的模型”写每日小结
@MainActor
final class DigestWriter {
    private let store: ContentStore
    private var running: Set<String> = []
    /// 自动写过（或失败过）的日子，本次运行不再自动重试，避免反复调用
    private var autoAttempted: Set<String> = []
    private var lastAutoCheck = Date.distantPast
    var onWritten: (Digest, _ automatic: Bool) -> Void = { _, _ in }

    init(store: ContentStore) {
        self.store = store
    }

    func digest(for day: Date) -> Digest? {
        try? store.digest(day: DayKey.string(day))
    }

    func isRunning(_ day: Date) -> Bool { running.contains(DayKey.string(day)) }

    /// 写（或重写）某一天的小结
    @discardableResult
    func write(day: Date, config: Config, automatic: Bool = false) async throws -> Digest {
        let key = DayKey.string(day)
        guard !running.contains(key) else { throw LLMError.api("正在写这一天的小结") }
        running.insert(key)
        defer { running.remove(key) }

        let (start, end) = LogicalDay.range(day)
        let views = try store.views(from: start, to: end)
        let reasons = try store.reasons(from: start, to: end)
        let nudges = try store.nudges(from: start, to: end)
        let prompt = DigestPrompt.make(day: day, views: views, reasons: reasons, nudges: nudges, config: config)

        let llm = config.llm
        let spec = ChatSpec(system: prompt.system, user: prompt.user, model: llm.reportModel, maxTokens: 8000,
                            effort: "medium", jsonSchema: DailyReport.schema, jsonExample: DailyReport.example)
        let request = try LLMRequest.chat(spec, llm: llm, apiKey: APIKeyStore.get(llm.provider), timeout: 300)
        let (data, _) = try await URLSession.shared.data(for: request)
        let report = try DailyReport.parse(try LLMResponse.text(data, provider: llm.provider))
        let digest = Digest(day: key, text: report.json, model: llm.reportModel)
        try store.saveDigest(digest)
        writeObsidian(folder: "每日小结", name: key, title: "\(key) 专注小结", kind: "每日小结", body: report.markdown, config: config)
        onWritten(digest, automatic)
        return digest
    }

    func weekly(for week: Week) -> Digest? {
        try? store.digest(day: week.key)
    }

    /// 写（或重写）某一周的复盘，存库并写进 Obsidian
    @discardableResult
    func writeWeekly(week: Week, config: Config, automatic: Bool = false) async throws -> Digest {
        guard !running.contains(week.key) else { throw LLMError.api("正在写这一周的复盘") }
        running.insert(week.key)
        defer { running.remove(week.key) }

        var days: [WeekDay] = []
        for day in week.days {
            let (start, end) = LogicalDay.range(day)
            days.append(WeekDay(day: day, views: try store.views(from: start, to: end),
                                reasons: try store.reasons(from: start, to: end).map(\.reason),
                                nudges: try store.nudges(from: start, to: end),
                                digest: try store.digest(day: DayKey.string(day)).map { $0.daily?.markdown ?? $0.text }))
        }
        let prompt = WeeklyPrompt.make(week: week, days: days, config: config)
        let llm = config.llm
        let spec = ChatSpec(system: prompt.system, user: prompt.user, model: llm.reportModel, maxTokens: 8000,
                            effort: "high", jsonSchema: WeeklyReport.schema, jsonExample: WeeklyReport.example)
        let request = try LLMRequest.chat(spec, llm: llm, apiKey: APIKeyStore.get(llm.provider), timeout: 300)
        let (data, _) = try await URLSession.shared.data(for: request)
        let report = try WeeklyReport.parse(try LLMResponse.text(data, provider: llm.provider))
        let digest = Digest(day: week.key, text: report.json, model: llm.reportModel)
        try store.saveDigest(digest)
        writeObsidian(folder: "每周复盘", name: week.key, title: "\(week.key) 专注复盘", kind: "每周复盘", body: report.markdown, config: config)
        onWritten(digest, automatic)
        return digest
    }

    /// 写进 Obsidian 的文件夹（关闭或找不到库时为 nil）
    static func obsidianRoot(_ config: Config) -> URL? {
        guard config.writeToObsidian else { return nil }
        if !config.obsidianFolder.isEmpty { return URL(fileURLWithPath: config.obsidianFolder) }
        return ObsidianNote.detectVault().map { URL(fileURLWithPath: $0).appendingPathComponent("专注守护") }
    }

    private(set) var obsidianError: String?

    private func writeObsidian(folder: String, name: String, title: String, kind: String, body: String, config: Config) {
        guard let root = Self.obsidianRoot(config) else { return }
        let dir = root.appendingPathComponent(folder)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let note = ObsidianNote.render(title: title, kind: kind, date: DayKey.string(Date()), body: body)
            try note.write(to: dir.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)
            obsidianError = nil
        } catch {
            obsidianError = "写入 Obsidian 失败：\(error.localizedDescription)"
        }
    }

    /// 每分钟检查一次：到点写今天的；昨天有记录但没写的补上
    func autoRun(config: Config, now: Date = Date()) {
        guard config.llm.enabled, now.timeIntervalSince(lastAutoCheck) >= 60 else { return }
        lastAutoCheck = now
        let cal = Calendar.current
        var days: [Date] = []
        days.append(LogicalDay.adding(-1, to: LogicalDay.of(now)))
        // 到点写今天的；凌晨 4 点前还算前一天，那时“今天”就是前一天，早过了写小结的点
        if cal.component(.hour, from: now) >= config.digestHour || LogicalDay.of(now) != cal.startOfDay(for: now) {
            days.append(LogicalDay.of(now))
        }

        // 上一周的复盘（周一起就可以写）
        let lastWeek = Week(containing: now).previous()
        if !autoAttempted.contains(lastWeek.key), weekly(for: lastWeek) == nil,
           !((try? store.views(from: lastWeek.start, to: lastWeek.end)) ?? []).isEmpty {
            autoAttempted.insert(lastWeek.key)
            Task { try? await writeWeekly(week: lastWeek, config: config, automatic: true) }
        }

        for day in days {
            let key = DayKey.string(day)
            guard !autoAttempted.contains(key), digest(for: day) == nil else { continue }
            let range = LogicalDay.range(day)
            let hasData = !((try? store.views(from: range.start, to: range.end)) ?? []).isEmpty
            guard hasData else { continue }
            autoAttempted.insert(key)
            Task { try? await write(day: day, config: config, automatic: true) }
        }
    }
}
