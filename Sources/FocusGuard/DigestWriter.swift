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

        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let views = try store.views(from: start, to: end)
        let reasons = try store.reasons(from: start, to: end)
        let nudges = try store.nudges(from: start, to: end)
        let prompt = DigestPrompt.make(day: day, views: views, reasons: reasons, nudges: nudges, config: config)

        let llm = config.llm
        let spec = ChatSpec(system: prompt.system, user: prompt.user, model: llm.reportModel,
                            maxTokens: 16000, effort: "medium")
        let request = try LLMRequest.chat(spec, llm: llm, apiKey: APIKeyStore.get(llm.provider), timeout: 300)
        let (data, _) = try await URLSession.shared.data(for: request)
        let text = try LLMResponse.text(data, provider: llm.provider)
        let digest = Digest(day: key, text: text.trimmingCharacters(in: .whitespacesAndNewlines), model: llm.reportModel)
        try store.saveDigest(digest)
        onWritten(digest, automatic)
        return digest
    }

    /// 每分钟检查一次：到点写今天的；昨天有记录但没写的补上
    func autoRun(config: Config, now: Date = Date()) {
        guard config.llm.enabled, now.timeIntervalSince(lastAutoCheck) >= 60 else { return }
        lastAutoCheck = now
        let cal = Calendar.current
        var days: [Date] = []
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now) { days.append(yesterday) }
        if cal.component(.hour, from: now) >= config.digestHour { days.append(now) }

        for day in days {
            let key = DayKey.string(day)
            guard !autoAttempted.contains(key), digest(for: day) == nil else { continue }
            let start = cal.startOfDay(for: day)
            let hasData = !((try? store.views(from: start, to: cal.date(byAdding: .day, value: 1, to: start)!)) ?? []).isEmpty
            guard hasData else { continue }
            autoAttempted.insert(key)
            Task { try? await write(day: day, config: config, automatic: true) }
        }
    }
}
