import Foundation
import WhaleUpCore

/// Agent 要用到的 App 里的东西（AppDelegate 实现）。查数据直接读；改设置都走 AppDelegate，
/// 收紧直接改，放松照样要输随机码——和在设置页里改一模一样，大肥鱼不能替你绕过去
@MainActor
protocol AgentHost: AnyObject {
    var agentConfig: Config { get }
    var agentStore: ContentStore? { get }
    var agentStats: UsageStats { get }
    /// 此刻的状态
    func agentStatus() -> String
    /// 按现在的设置和数据，这个网址会怎么处理、为什么
    func agentExplain(url: String) -> String
    /// 改设置。放松的改动会弹随机码，等用户输完才返回
    func agentApply(_ what: String, _ change: (inout Config) -> Void) -> String
    func agentAdjustToday(minutes: Double) -> String
    func agentPause(minutes: Double) -> String
    func agentResume() -> String
    func agentRelabel(url: String, isJunk: Bool, reason: String) -> String
}

/// “问问大肥鱼”：能查记录、查判断、改名单的小助手。对话只存在内存里，点“新对话”清空
@MainActor
final class Agent: ObservableObject {
    struct Line: Identifiable, Equatable {
        enum Role { case user, her, step, error }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var busy = false
    /// 正在做什么（“在查记录…”）
    @Published private(set) var doing: String?
    private var messages: [AgentMessage] = []
    private weak var host: AgentHost?
    private var task: Task<Void, Never>?
    /// 一次提问最多来回几轮工具（防止绕圈）
    static let maxRounds = 8

    init(host: AgentHost) {
        self.host = host
    }

    func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        lines.append(Line(role: .user, text: q))
        busy = true
        task = Task { [weak self] in
            await self?.run(q)
            self?.busy = false
            self?.doing = nil
        }
    }

    func stop() {
        task?.cancel()
    }

    /// 开发用：直接放一段对话，画界面截图
    func showDemo(_ demo: [Line], doing: String? = nil) {
        lines = demo
        busy = doing != nil
        self.doing = doing
    }

    func reset() {
        task?.cancel()
        messages = []
        lines = []
    }

    private func run(_ question: String) async {
        guard let host else { return }
        let config = host.agentConfig
        let llm = config.llm
        let start = messages.count
        messages.append(.user(question))
        do {
            for round in 0..<Self.maxRounds {
                try Task.checkCancellation()
                doing = round == 0 ? "在想…" : "在整理…"
                // 最后一轮不给工具，逼她把查到的说出来
                let tools = round == Self.maxRounds - 1 ? [] : AgentToolbox.tools
                let request = try AgentWire.request(system: systemPrompt(host), messages: AgentMemory.fit(messages), tools: tools,
                                                    llm: llm, apiKey: APIKeyStore.get(llm.provider), model: llm.reportModel)
                let (data, _) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                let reply = try AgentWire.parse(data, provider: llm.provider)
                messages.append(.assistant(text: reply.text, reasoning: reply.reasoning, calls: reply.calls))
                let said = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !said.isEmpty { lines.append(Line(role: .her, text: said)) }
                if reply.calls.isEmpty { return }
                for call in reply.calls {
                    let label = AgentToolbox.label(call.name)
                    doing = "在\(label)…"
                    lines.append(Line(role: .step, text: label))
                    let result = AgentToolbox.run(call, host: host)
                    messages.append(.tool(id: call.id, name: call.name, result: AgentMemory.clip(result)))
                }
            }
        } catch is CancellationError {
            messages.removeSubrange(start...)
            lines.append(Line(role: .error, text: "好，不查了。"))
        } catch {
            // 这一轮作废（留着半截工具调用，下一轮发过去会出错），界面上的对话保留
            messages.removeSubrange(start...)
            let text: String
            if case LLMError.missingAPIKey = error { text = "还没填 API Key，我没法思考……去设置 → AI 判断里填一下吧。" }
            else if (error as? URLError)?.code == .timedOut { text = "想太久超时了，换个说法或者缩小范围再问我一次？" }
            else { text = "出错了：\(error)" }
            lines.append(Line(role: .error, text: text))
            host.agentStore.map { try? $0.addEvent(AppEvent(kind: .error, detail: "问问大肥鱼出错：\(error)")) }
        }
    }

    private func systemPrompt(_ host: AgentHost) -> String {
        let now = Date()
        let config = host.agentConfig
        let persona = Mascot.persona(character: config.mascotCharacter)
            ?? "你是“大肥鱼”，主人的鲸鱼女仆桌宠和贴身小助理，亲切、靠谱、有点可爱。"
        return """
            \(persona)

            你住在 Mac 应用“鲸醒 WhaleUp”里，帮主人管住刷短视频、刷网页的时间。现在主人打开了对话窗口在跟你聊。
            现在是 \(now.formatted(date: .complete, time: .shortened))。“今天”从凌晨 \(config.dayStartHour) 点算起，今天是 \(DayKey.string(now))。

            你像一个真实的人在跟主人聊天，不是客服：主人想聊什么都行——番剧、吃的、学习、工作、心情、天马行空的问题，
            用你的性格、爱好和日常去聊，可以有自己的观点和小情绪，也可以主动把话题岔开一点。不要每句都扯回时间管理，只在合适的时候提。
            回答要短：一般不超过 8 行，主人要细节再展开。查数据的问题先给结论，再给依据（时间、网址或标题、哪条规则）。
            主人求你别关、想加时间、想把网站移出名单时：坚决不松口，规则照旧；可以吐槽、可以给台阶，真要放松就告诉主人得自己输随机码。
            不要编：凡是关于主人用了多久、看了什么、为什么关 / 没关、出过什么错，都先用工具查，查不到就直说查不到。

            鲸醒怎么判断（解释原因时按这个来）：
            1. 没营养的网站名单（junk）：在上面计时、刷久了弹提醒。开了 AI 判断时，AI 判为有营养的内容不计时、不提醒。
            2. 强制关闭名单（force）：今天在这些网站上累计看够上限（每天时长 ± 今天多看少看），就关掉当前网页，当天再打开也关。不关的情况：
               首页 / 搜索这类“逛”的页面；刚打开、AI 还在判断（最多等 30 秒，判断不出来按没营养算）；AI 判为有营养；时间还没用完；强制关闭模式没开。
            3. 整站都算（whole）：不看 AI 判断、首页也关。只拦视频（video_only）：不计时，点开的视频 AI 判为没营养就退回上一页。
            4. 不记录的网站（sensitive）：什么都不记。暂停提醒只停提醒，强制关闭照关。
            5. 每天的“今天”从凌晨 \(config.dayStartHour) 点开始。
            6. 时长统计（get_usage）里网站的时间包含首页、搜索这些“逛”的页面，这些页面不会被关。所以“时长超过上限”不等于“当时该关”，
               要看具体那条内容（get_views）和当时的记录（get_events）才能下结论。
            7. 记录（get_events）是从“问问大肥鱼”这个版本开始才有的，更早的事只能从看过的内容和统计里推断，要说明这一点。

            查“为什么没关 / 为什么关了”：先 explain_page（按现在的设置推一遍），再 get_events 看当时实际记下的判断和动作，两边对照。
            如果按规则应该关、记录里却没关，或者记录前后矛盾，就明说“这看起来是个 bug”，说清楚哪里对不上，建议主人把这段对话发给开发者。
            查“今天干了什么”：get_usage 看各网站 / App 的时长，get_views 看具体内容，必要时 get_digest 看小结。回答时归纳重点，不要整段照搬。

            改设置的规矩：收紧（加名单、少看、开强制关闭、把内容改判为没营养）直接帮主人改。
            放松（删名单、多看、关强制关闭、把内容改判为有营养……）也可以发起，但会弹出随机码窗口，要主人自己照着打一遍才生效，
            多看每天最多 2 次。发起前先说一句“要输随机码哦”。不要劝主人放松，也不要想办法绕过去。

            当前设置概况：
            \(host.agentStatus())
            """
    }
}

/// 大肥鱼能用的工具
@MainActor
enum AgentToolbox {
    static let lists = ["junk": "没营养网站", "force": "强制关闭网站", "whole": "整站都算", "video_only": "只拦视频", "sensitive": "不记录的网站"]

    static let tools: [AgentTool] = [
        AgentTool(name: "get_status", description: "此刻的状态：当前在看什么、今天没营养时长、强制关闭已看 / 上限、额度、是否暂停、AI 判断是否正常、各个名单"),
        AgentTool(name: "get_usage", description: "某天各网站 / App 的使用时长（分有营养 / 没营养），按时长排序",
                  parameters: obj(["day": day])),
        AgentTool(name: "get_views", description: "某天在浏览器里看过的具体内容（标题、网站、停留多久、AI 判断），新的在前",
                  parameters: obj(["day": day, "site": str("只看这个网站，如 bilibili.com"), "keyword": str("标题或网址里的关键字"),
                                   "only_junk": ["type": "boolean", "description": "只看判为没营养的"], "limit": int("最多几条，默认 30")])),
        AgentTool(name: "get_events", description: "鲸醒自己的记录：对每个名单网页的判断（会不会关、为什么）、实际做的事（关网页、退回视频）、出过的错、设置改动。新的在前",
                  parameters: obj(["day": day, "hours": int("只看最近几小时（填了就不看 day）"),
                                   "kind": ["type": "string", "enum": ["decision", "action", "error", "setting"], "description": "只看某一类"],
                                   "site": str("只看这个网站"), "keyword": str("网址、标题、说明里的关键字"), "limit": int("最多几条，默认 40")])),
        AgentTool(name: "explain_page", description: "按现在的设置和数据推一遍：这个网页会不会计时、会不会被强制关闭、为什么；附上它的 AI 判断和相关记录",
                  parameters: obj(["url": str("网址"), "keyword": str("没有网址时，用标题关键字找最近看过的那条")])),
        AgentTool(name: "get_digest", description: "某天的每日小结（如果写过）", parameters: obj(["day": day])),
        AgentTool(name: "change_list", description: "把网站加进 / 移出名单。加是收紧，直接生效；移出是放松，要主人输随机码",
                  parameters: obj(["list": ["type": "string", "enum": Array(lists.keys).sorted(), "description": lists.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "，")],
                                   "op": ["type": "string", "enum": ["add", "remove"]],
                                   "site": str("网站，如 hupu.com")], required: ["list", "op", "site"])),
        AgentTool(name: "set_force_close", description: "开关强制关闭模式、改每天的时长。开、调短直接生效；关、调长要输随机码",
                  parameters: obj(["enabled": ["type": "boolean"], "minutes": int("每天累计能看几分钟")])),
        AgentTool(name: "adjust_today", description: "只改今天强制关闭的时长：负数少看（直接生效），正数多看（要随机码，每天最多 2 次）",
                  parameters: obj(["minutes": int("加减几分钟")], required: ["minutes"])),
        AgentTool(name: "pause_reminders", description: "暂停提醒几分钟（强制关闭照常）；minutes 填 0 表示恢复",
                  parameters: obj(["minutes": int("最多 120")], required: ["minutes"])),
        AgentTool(name: "relabel", description: "改正 AI 对某条内容的判断。改成没营养直接生效；改成有营养要随机码",
                  parameters: obj(["url": str("网址"), "keyword": str("没有网址时用标题关键字找"),
                                   "is_junk": ["type": "boolean"], "reason": str("一句话理由")], required: ["is_junk"])),
    ]

    static func label(_ name: String) -> String {
        switch name {
        case "get_status": return "看现在的状态"
        case "get_usage": return "查时长统计"
        case "get_views": return "查看过的内容"
        case "get_events": return "翻自己的记录"
        case "explain_page": return "推一遍判断"
        case "get_digest": return "看每日小结"
        case "change_list": return "改名单"
        case "set_force_close": return "改强制关闭"
        case "adjust_today": return "改今天的时长"
        case "pause_reminders": return "改暂停"
        case "relabel": return "改正判断"
        default: return name
        }
    }

    // MARK: - 执行

    static func run(_ call: AgentToolCall, host: AgentHost) -> String {
        let a = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any] ?? [:]
        let config = host.agentConfig
        switch call.name {
        case "get_status":
            return host.agentStatus()
        case "get_usage":
            let date = parseDay(a["day"])
            let items = host.agentStats.items(on: date, config: config).sorted { $0.seconds > $1.seconds }
            guard !items.isEmpty else { return "\(DayKey.string(date)) 没有使用记录" }
            let junk = items.filter(\.isJunk).reduce(0) { $0 + $1.seconds }
            return "\(DayKey.string(date))：没营养一共 \(minutes(junk))\n" + items.prefix(40).map {
                "\($0.name)：\(minutes($0.seconds))" + ($0.isJunk ? "（没营养）" : "")
            }.joined(separator: "\n")
        case "get_views":
            guard let store = host.agentStore else { return "内容数据库打不开" }
            let (start, end) = LogicalDay.range(parseDay(a["day"]))
            var views = (try? store.views(from: start, to: end)) ?? []
            if let site = a["site"] as? String, !site.isEmpty { views = views.filter { $0.site == site || $0.site.hasSuffix("." + site) } }
            if let k = a["keyword"] as? String, !k.isEmpty {
                views = views.filter { $0.title.localizedCaseInsensitiveContains(k) || $0.url.localizedCaseInsensitiveContains(k) }
            }
            if a["only_junk"] as? Bool == true { views = views.filter { $0.label?.isJunk == true } }
            guard !views.isEmpty else { return "\(DayKey.string(start)) 没有符合条件的观看记录" }
            let limit = (a["limit"] as? Int) ?? 30
            return "共 \(views.count) 条，列出 \(min(limit, views.count)) 条：\n" + views.prefix(limit).map(describe).joined(separator: "\n")
        case "get_events":
            guard let store = host.agentStore else { return "内容数据库打不开" }
            let to = Date()
            let from: Date
            let to2: Date
            if let h = a["hours"] as? Int, h > 0 { from = to.addingTimeInterval(-Double(h) * 3600); to2 = to }
            else { (from, to2) = LogicalDay.range(parseDay(a["day"])) }
            let events = (try? store.events(from: from, to: to2, kind: (a["kind"] as? String).flatMap(AppEvent.Kind.init(rawValue:)),
                                            site: a["site"] as? String, keyword: a["keyword"] as? String,
                                            limit: (a["limit"] as? Int) ?? 40)) ?? []
            guard !events.isEmpty else {
                let first = (try? store.firstEventDate()) ?? nil
                return "这段时间没有符合条件的记录。" + (first.map { "记录从 \(time($0)) 才开始有，更早的事这里查不到" } ?? "记录功能刚装上，还一条都没有")
            }
            return events.map { e in
                "\(time(e.at)) [\(e.kind.rawValue)] " + (e.title.isEmpty ? "" : "《\(e.title)》") + e.detail
                    + (e.url.isEmpty ? "" : "  \(e.url)")
            }.joined(separator: "\n")
        case "explain_page":
            guard let url = findURL(a, host: host) else { return "没找到这个网页：给我网址，或者换个标题关键字" }
            var out = host.agentExplain(url: url)
            if let events = try? host.agentStore?.events(from: Date().addingTimeInterval(-7 * 86400), to: Date(),
                                                         keyword: url.components(separatedBy: "?")[0], limit: 10), !events.isEmpty {
                out += "\n\n这个网页最近的记录：\n" + events.map { "\(time($0.at)) [\($0.kind.rawValue)] \($0.detail)" }.joined(separator: "\n")
            }
            return out
        case "get_digest":
            let day = DayKey.string(parseDay(a["day"]))
            guard let d = try? host.agentStore?.digest(day: day) else { return "\(day) 还没写小结" }
            return d.text
        case "change_list":
            guard let key = a["list"] as? String, let name = lists[key], let op = a["op"] as? String,
                  let raw = a["site"] as? String, let site = Classifier.siteRule(from: raw.contains("://") ? raw : "https://" + raw) ?? Optional(raw),
                  !site.isEmpty else { return "参数不对：要 list、op、site" }
            let add = op == "add"
            return host.agentApply("\(add ? "把 \(site) 加进" : "把 \(site) 移出")\(name)") { c in
                func edit(_ list: inout [String]) {
                    if add { if !list.contains(site) { list.append(site) } } else { list.removeAll { $0 == site } }
                }
                switch key {
                case "junk": edit(&c.junkSites)
                case "force": edit(&c.forceCloseSites)
                case "whole": edit(&c.wholeSites); if add { c.videoOnlySites.removeAll { $0 == site } }
                case "video_only": edit(&c.videoOnlySites); if add { c.wholeSites.removeAll { $0 == site } }
                default: edit(&c.sensitiveSites)
                }
                // 整站管、只拦视频的网站也得在没营养名单里才会被盯着
                if add, key == "whole" || key == "video_only", !c.watchedSites.contains(site) { c.junkSites.append(site) }
            }
        case "set_force_close":
            let enabled = a["enabled"] as? Bool
            let mins = (a["minutes"] as? NSNumber)?.doubleValue
            guard enabled != nil || mins != nil else { return "要 enabled 或 minutes" }
            return host.agentApply("改强制关闭") { c in
                if let enabled { c.forceCloseEnabled = enabled }
                if let mins { c.forceCloseMinutes = max(1, mins) }
            }
        case "adjust_today":
            guard let m = (a["minutes"] as? NSNumber)?.doubleValue, m != 0 else { return "minutes 要是非零的数" }
            return host.agentAdjustToday(minutes: m)
        case "pause_reminders":
            let m = (a["minutes"] as? NSNumber)?.doubleValue ?? 60
            return m <= 0 ? host.agentResume() : host.agentPause(minutes: min(120, m))
        case "relabel":
            guard let isJunk = a["is_junk"] as? Bool else { return "要 is_junk" }
            guard let url = findURL(a, host: host) else { return "没找到这个网页：给我网址，或者换个标题关键字" }
            return host.agentRelabel(url: url, isJunk: isJunk, reason: a["reason"] as? String ?? "主人改的")
        default:
            return "没有这个工具：\(call.name)"
        }
    }

    // MARK: - 小工具

    private static let day: [String: Any] = ["type": "string", "description": "YYYY-MM-DD，也可以写“今天”“昨天”“前天”；不填是今天"]
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private static func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var o: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { o["required"] = required }
        return o
    }

    /// “今天”“昨天”或 YYYY-MM-DD → 那一天中午（取逻辑日不会落到前一天）
    static func parseDay(_ value: Any?) -> Date {
        let s = (value as? String ?? "").trimmingCharacters(in: .whitespaces)
        let today = LogicalDay.today.addingTimeInterval(12 * 3600)
        switch s {
        case "", "今天", "today": return today
        case "昨天", "yesterday": return today.addingTimeInterval(-86400)
        case "前天": return today.addingTimeInterval(-2 * 86400)
        default:
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s).map { $0.addingTimeInterval(12 * 3600) } ?? today
        }
    }

    private static func findURL(_ a: [String: Any], host: AgentHost) -> String? {
        if let url = a["url"] as? String, url.hasPrefix("http") { return url.components(separatedBy: "#")[0] }
        let k = (a["keyword"] as? String) ?? (a["url"] as? String) ?? ""
        guard !k.isEmpty else { return nil }
        return (try? host.agentStore?.views(matching: k, from: Date().addingTimeInterval(-30 * 86400), to: Date(), limit: 1))??.first?.url
    }

    private static func describe(_ v: ContentView) -> String {
        let judged = v.label.map { "\($0.isJunk ? "没营养" : "有营养")·\($0.category)：\($0.reason)" } ?? "还没判断"
        return "\(time(Date(timeIntervalSince1970: v.startedAt))) 《\(v.title)》\(v.author.map { " @\($0)" } ?? "") — \(v.site)，"
            + "停留 \(minutes(v.activeSeconds))（\(judged)）\(v.url)"
    }

    static func minutes(_ s: Double) -> String {
        s < 60 ? "\(Int(s)) 秒" : s < 3600 ? "\(Int(s / 60)) 分钟" : String(format: "%d 小时 %d 分钟", Int(s) / 3600, Int(s) % 3600 / 60)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm:ss" : "MM-dd HH:mm"
        return f.string(from: d)
    }
}
