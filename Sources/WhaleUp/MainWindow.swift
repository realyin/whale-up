import AppKit
import Charts
import SwiftUI
import WhaleUpCore

// MARK: - 模型

enum Page: String, CaseIterable, Identifiable {
    case today = "今天", timeline = "时间线", content = "内容", favorites = "收藏", trends = "趋势", reports = "报告", settings = "设置"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .timeline: return "clock"
        case .content: return "list.bullet.rectangle"
        case .favorites: return "star"
        case .trends: return "chart.bar.xaxis"
        case .reports: return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

/// 主窗口的数据。数据库和统计由 AppDelegate 维护，这里只读；有变化时 version +1 让界面刷新。
@MainActor
final class MainModel: ObservableObject {
    @Published var page: Page = .today
    @Published var stats: UsageStats
    @Published var config: Config
    @Published var version = 0
    @Published var pausedUntil: Date?
    /// 今天累计的没营养秒数（和提醒用的同一个数）
    @Published var todayJunkSeconds: Double = 0
    var contentStore: ContentStore?
    var digestWriter: DigestWriter?
    var favorites: FavoriteExtractor?
    let settings: SettingsModel

    var deleteDay: (Date) -> Void = { _ in }
    var deleteSite: (String) -> Void = { _ in }
    var togglePause: () -> Void = {}

    init(stats: UsageStats, config: Config, settings: SettingsModel) {
        self.stats = stats
        self.config = config
        self.settings = settings
    }

    func views(on day: Date) -> [ContentView] {
        let range = LogicalDay.range(day)
        return (try? contentStore?.views(from: range.start, to: range.end)) ?? []
    }
}

@MainActor
final class MainWindow {
    let model: MainModel
    private var window: NSWindow?

    init(model: MainModel) {
        self.model = model
    }

    func show(_ page: Page? = nil) {
        if let page { model.page = page }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model)))
            window.title = "鲸醒"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 1040, height: 720))
            window.minSize = NSSize(width: 880, height: 600)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("WhaleUpMain")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 开发用：把某一页画成 PNG
    static func renderPNG(model: MainModel, page: Page, to url: URL, size: NSSize = NSSize(width: 1040, height: 720)) {
        model.page = page
        let view = NSHostingView(rootView: MainView(model: model).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - 样式

/// 有营养 / 没营养的颜色（色盲友好的蓝 / 橙，分别适配浅色和深色）
enum NutritionColor {
    static let good = dynamic(light: 0x2a78d6, dark: 0x3987e5)
    static let junk = dynamic(light: 0xeb6834, dark: 0xd95926)

    private static func dynamic(light: Int, dark: Int) -> Color {
        func ns(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
    }
}

/// 教练说的话用衬线体（中文落到宋体），和界面里冷静的数据区分开
extension Font {
    static let coach = Font.system(size: 26, weight: .regular, design: .serif)
    static let coachSmall = Font.system(size: 17, weight: .regular, design: .serif)
}

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    if seconds > 0 && minutes < 1 { return "不到 1 分钟" }
    if minutes < 60 { return "\(minutes) 分钟" }
    return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
}

func clock(_ t: Double) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
    return String(format: "%02d:%02d", c.hour!, c.minute!)
}

func dayTitle(_ day: Date) -> String {
    if LogicalDay.isToday(day) { return "今天" }
    if LogicalDay.of(day) == LogicalDay.adding(-1, to: LogicalDay.today) { return "昨天" }
    return day.formatted(.dateTime.month().day().weekday(.wide))
}

// MARK: - 主界面

struct MainView: View {
    @ObservedObject var model: MainModel

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) { page in
                Label(page.rawValue, systemImage: page.icon).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch model.page {
                case .today: TodayPage(model: model)
                case .timeline: TimelinePage(model: model)
                case .content: ContentPage(model: model)
                case .favorites: FavoritesPage(model: model)
                case .trends: TrendsPage(model: model)
                case .reports: ReportsPage(model: model)
                case .settings: SettingsView(model: model.settings, tab: .sites, embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 页面统一的外边距和标题
struct PageScaffold<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 22, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) }
                Spacer()
                accessory
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)
            content
        }
    }
}

/// 日期切换：‹ 今天 ›
struct DayStepper: View {
    @Binding var day: Date

    var body: some View {
        HStack(spacing: 2) {
            Button { day = LogicalDay.adding(-1, to: day) } label: { Image(systemName: "chevron.left") }
            Text(dayTitle(day)).font(.system(size: 13, weight: .medium)).frame(minWidth: 96)
            Button { day = LogicalDay.adding(1, to: day) } label: { Image(systemName: "chevron.right") }
                .disabled(LogicalDay.isToday(day))
            if !LogicalDay.isToday(day) {
                Button("回到今天") { day = LogicalDay.today }.buttonStyle(.link).padding(.leading, 6)
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 当天色带：0–24 点，每段浏览按有营养 / 没营养着色

struct DayRibbon: View {
    let day: Date
    let sessions: [TimelineSession]
    var height: CGFloat = 36
    @State private var hovered: TimelineSession?
    @State private var hoverX: CGFloat = 0

    var body: some View {
        let start = LogicalDay.range(day).start.timeIntervalSince1970
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (t: Double) in CGFloat((t - start) / 86400) * w }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10))
                    ForEach([6.0, 12, 18], id: \.self) { h in
                        Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 1).offset(x: CGFloat(h / 24) * w)
                    }
                    ForEach(sessions) { s in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(s.isJunk ? NutritionColor.junk : NutritionColor.good)
                            .opacity(hovered == nil || hovered?.id == s.id ? 1 : 0.45)
                            .frame(width: max(3, x(s.end) - x(s.start)), height: height - 10)
                            .offset(x: x(s.start), y: 5)
                    }
                    if LogicalDay.isToday(day) {
                        Rectangle().fill(Color.primary).frame(width: 2, height: height + 6)
                            .offset(x: x(Date().timeIntervalSince1970), y: -3)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let t = start + Double(p.x / w) * 86400
                        hovered = sessions.min { a, b in distance(t, a) < distance(t, b) }
                            .flatMap { distance(t, $0) < 86400 * 6 / Double(w) ? $0 : nil }
                        hoverX = p.x
                    case .ended:
                        hovered = nil
                    }
                }
            }
            .frame(height: height)

            ZStack(alignment: .leading) {
                HStack {
                    // 从一天开始的那个小时排起，如 4:00 … 第二天 4:00
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text("\((LogicalDay.startHour + h) % 24):00").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("\(LogicalDay.startHour == 0 ? 24 : LogicalDay.startHour):00").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .opacity(hovered == nil ? 1 : 0)
                if let s = hovered {
                    Text("\(clock(s.start))–\(clock(s.end))  \(s.isJunk ? "🍟" : "🥦") \(s.site) · \(s.items.count > 1 ? "\(s.items.count) 条 · " : "")\(formatDuration(s.activeSeconds))  \(s.items.last?.title ?? "")")
                        .font(.system(size: 12)).lineLimit(1)
                }
            }
        }
    }

    private func distance(_ t: Double, _ s: TimelineSession) -> Double {
        t < s.start ? s.start - t : (t > s.end ? t - s.end : 0)
    }
}

// MARK: - 今天

struct TodayPage: View {
    @ObservedObject var model: MainModel
    @State private var writing = false
    @State private var error: String?

    var body: some View {
        let _ = model.version
        let today = LogicalDay.today
        let views = model.views(on: today)
        let timeline = Timeline.build(views: views, config: model.config)
        let goodSeconds = timeline.sessions.reduce(0) { $0 + $1.activeSeconds - $1.junkSeconds }
        let digest = model.digestWriter?.digest(for: today)

        PageScaffold(title: "今天", subtitle: Date().formatted(.dateTime.month().day().weekday(.wide))) {
            Button(model.pausedUntil == nil ? "暂停提醒 1 小时" : "恢复监测") { model.togglePause() }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    coachNote(digest)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(sentence(junk: model.todayJunkSeconds, good: goodSeconds))
                            .font(.system(size: 17)).lineSpacing(4)
                        DayRibbon(day: today, sessions: timeline.sessions)
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 40) {
                        siteColumn(title: "没营养的", items: junkItems(), color: NutritionColor.junk)
                        siteColumn(title: "有营养的", items: goodItems(timeline), color: NutritionColor.good)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: 880, alignment: .leading)
            }
        }
    }

    private func sentence(junk: Double, good: Double) -> String {
        var s = junk < 60 && good < 60 ? "今天还没有浏览记录。"
            : "今天在没营养的内容上花了 \(formatDuration(junk))，有营养的 \(formatDuration(good))。"
        if let left = model.config.budgetRemainingSeconds(usedToday: model.todayJunkSeconds) {
            s += left > 0 ? "额度还剩 \(formatDuration(left))。" : "今天的额度已经用完了。"
        }
        if let until = model.pausedUntil { s += "监测已暂停，\(clock(until.timeIntervalSince1970)) 恢复。" }
        return s
    }

    @ViewBuilder
    private func coachNote(_ digest: Digest?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = digest?.daily {
                Text(report.headline).font(.coach).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.findings, id: \.self) { f in
                        Text(f).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Text("明天：\(report.tomorrow)").font(.system(size: 14, weight: .medium))
                    SuggestionButton(suggestion: report.setting, model: model)
                }
                HStack(spacing: 12) {
                    Text("\(digest!.model) 写于 \(clock(digest!.createdAt))").font(.system(size: 11)).foregroundStyle(.tertiary)
                    writeButton("重新写")
                }
            } else if model.config.llm.enabled {
                Text("今晚 \(model.config.digestHour):00 写今天的小结").font(.coachSmall).foregroundStyle(.secondary)
                writeButton("现在就写")
            } else {
                Text("开启 AI 判断后，每晚会在这里写一句今天的小结").font(.coachSmall).foregroundStyle(.secondary)
                Button("去设置") { model.settings.tab = .ai; model.page = .settings }.buttonStyle(.link)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
        }
        .padding(.top, 4)
    }

    private func writeButton(_ title: String) -> some View {
        Button(writing ? "正在写…" : title) {
            guard let writer = model.digestWriter else { return }
            writing = true
            error = nil
            let config = model.config
            Task {
                do { try await writer.write(day: Date(), config: config) } catch { self.error = "\(error)" }
                writing = false
                model.version += 1
            }
        }
        .buttonStyle(.link).font(.system(size: 12)).disabled(writing)
    }

    private func junkItems() -> [(String, Double)] {
        model.stats.items(on: Date(), config: model.config).filter(\.isJunk).prefix(5).map { ($0.name, $0.seconds) }
    }

    private func goodItems(_ t: TimelineDay) -> [(String, Double)] {
        var bySite: [String: Double] = [:]
        for s in t.sessions { bySite[s.site, default: 0] += s.activeSeconds - s.junkSeconds }
        return bySite.filter { $0.value >= 30 }.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private func siteColumn(title: String, items: [(String, Double)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("没有").font(.system(size: 13)).foregroundStyle(.tertiary)
            }
            let maxValue = items.first?.1 ?? 1
            ForEach(items, id: \.0) { name, seconds in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text(formatDuration(seconds)).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: max(3, g.size.width * seconds / maxValue))
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 时间线

struct TimelinePage: View {
    @ObservedObject var model: MainModel
    @State private var day = LogicalDay.today
    @State private var expanded: Set<String> = []

    var body: some View {
        let _ = model.version
        let timeline = Timeline.build(views: model.views(on: day), config: model.config)
        let junk = timeline.sessions.reduce(0) { $0 + $1.junkSeconds }
        let total = timeline.sessions.reduce(0) { $0 + $1.activeSeconds }

        PageScaffold(title: "时间线") {
            DayStepper(day: $day)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                DayRibbon(day: day, sessions: timeline.sessions, height: 44)
                    .padding(.horizontal, 32)
                if timeline.sessions.isEmpty {
                    emptyState
                } else {
                    Text("没营养 \(formatDuration(junk))，有营养 \(formatDuration(total - junk))，共 \(timeline.sessions.count) 段")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 32)
                    List {
                        ForEach(groupedByHour(timeline.sessions), id: \.0) { hour, sessions in
                            Section("\(hour):00") {
                                ForEach(sessions) { s in
                                    row(s).contextMenu {
                                        ForEach(s.items.suffix(5), id: \.viewId) { v in
                                            Button("收藏「\(v.title.prefix(24))」") { favoriteFromHistory(v, model: model) }
                                        }
                                        Divider()
                                        Button("删除 \(s.site) 的所有记录…") { confirmDeleteSite(s.site, model: model) }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    HStack {
                        Spacer()
                        Button("删除这一天的全部记录…") { confirmDeleteDay(day, model: model) }
                            .buttonStyle(.link).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32).padding(.bottom, 14)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这一天没有浏览记录").font(.system(size: 15))
            Text(model.config.contentScope == .all ? "装好浏览器扩展后，浏览的网页会出现在这里。"
                 : "现在只记录没营养的网站。想看到全天的时间线，在设置的“内容记录”里选“记录所有网页”。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32).padding(.top, 24)
    }

    private func groupedByHour(_ sessions: [TimelineSession]) -> [(Int, [TimelineSession])] {
        let groups = Dictionary(grouping: sessions) { Calendar.current.component(.hour, from: Date(timeIntervalSince1970: $0.start)) }
        // 从一天开始的那个小时排起（凌晨的排在最后）
        let order = { (h: Int) in (h - LogicalDay.startHour + 24) % 24 }
        return groups.keys.sorted { order($0) < order($1) }.map { ($0, groups[$0]!) }
    }

    private func row(_ s: TimelineSession) -> some View {
        let open = expanded.contains(s.id)
        return HStack(alignment: .top, spacing: 12) {
            Text(clock(s.start)).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(s.isJunk ? NutritionColor.junk : NutritionColor.good).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(s.site).font(.system(size: 13, weight: .semibold))
                    Text(s.items.count > 1 ? "\(s.items.count) 条，\(formatDuration(s.activeSeconds))" : formatDuration(s.activeSeconds))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(open ? s.items : Array(s.items.prefix(2)), id: \.viewId) { v in
                    HStack(spacing: 6) {
                        Text(v.isJunk(config: model.config) ? "🍟" : "🥦").font(.system(size: 11))
                        Text(v.title.isEmpty ? v.url : v.title).font(.system(size: 13)).lineLimit(1)
                        if let l = v.label { Text(l.category).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }
                if s.items.count > 2 {
                    Button(open ? "收起" : "还有 \(s.items.count - 2) 条") {
                        if open { expanded.remove(s.id) } else { expanded.insert(s.id) }
                    }
                    .buttonStyle(.link).font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 内容

struct ContentRow: Identifiable {
    let view: ContentView
    var id: String { view.viewId }
}

struct ContentPage: View {
    @ObservedObject var model: MainModel
    @State private var range = 1
    @State private var filter = 0
    @State private var search = ""
    @State private var selection = Set<String>()

    var body: some View {
        let _ = model.version
        let rows = load()
        PageScaffold(title: "内容", subtitle: "\(rows.count) 条") {
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    Text("全部").tag(0)
                    Text("有营养").tag(1)
                    Text("没营养").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Picker("", selection: $range) {
                    Text("今天").tag(1)
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .labelsHidden().frame(width: 100)
            }
        } content: {
            Table(rows, selection: $selection) {
                TableColumn("时间") { r in
                    Text(range == 1 ? clock(r.view.startedAt)
                         : Date(timeIntervalSince1970: r.view.startedAt).formatted(.dateTime.month(.defaultDigits).day().hour().minute()))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: range == 1 ? 50 : 110, max: 130)
                TableColumn("") { r in
                    Text(favoriteURLs.contains(r.view.url) ? "⭐" : (r.view.isJunk(config: model.config) ? "🍟" : "🥦"))
                }
                .width(22)
                TableColumn("标题") { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.view.title.isEmpty ? r.view.url : r.view.title).lineLimit(1)
                        if let l = r.view.label {
                            Text(l.reason).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .width(min: 240, ideal: 380)
                TableColumn("网站") { r in Text(r.view.site).foregroundStyle(.secondary) }.width(min: 90, ideal: 120)
                TableColumn("作者") { r in Text(r.view.author ?? "").foregroundStyle(.secondary).lineLimit(1) }.width(min: 60, ideal: 100)
                TableColumn("判断") { r in
                    if let l = r.view.label {
                        Text("\(l.category) \(l.nutrition)/5").foregroundStyle(.secondary)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(min: 60, ideal: 80)
                TableColumn("时长") { r in
                    Text(r.view.activeSeconds < 60 ? "\(Int(r.view.activeSeconds)) 秒" : formatDuration(r.view.activeSeconds))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 70)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let v = rows.first(where: { $0.id == id })?.view {
                    Button("收藏并提取要点") { favorite(v) }
                    Button("在浏览器中打开") { if let u = URL(string: v.url) { NSWorkspace.shared.open(u) } }
                    Button("删除 \(v.site) 的所有记录…") { confirmDeleteSite(v.site, model: model) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let v = rows.first(where: { $0.id == id })?.view, let u = URL(string: v.url) {
                    NSWorkspace.shared.open(u)
                }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "搜索标题、网站、作者")
        }
    }

    private var favoriteURLs: Set<String> { (try? model.contentStore?.favoriteURLs()) ?? [] }

    private func favorite(_ v: ContentView) {
        favoriteFromHistory(v, model: model)
    }

    private func load() -> [ContentRow] {
        let end = Date()
        let start = LogicalDay.range(LogicalDay.adding(-(range - 1), to: LogicalDay.of(end))).start
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return ((try? model.contentStore?.views(from: start, to: end.addingTimeInterval(60))) ?? [])
            .filter { v in
                switch filter {
                case 1: return !v.isJunk(config: model.config)
                case 2: return v.isJunk(config: model.config)
                default: return true
                }
            }
            .filter { v in
                q.isEmpty || [v.title, v.site, v.author ?? ""].contains { $0.lowercased().contains(q) }
            }
            .map(ContentRow.init)
    }
}

// MARK: - 趋势

struct DayBar: Identifiable {
    let day: Date
    let kind: String
    let minutes: Double
    var id: String { "\(day.timeIntervalSince1970)\(kind)" }
}

struct TrendsPage: View {
    @ObservedObject var model: MainModel
    @State private var range = 7

    var body: some View {
        let _ = model.version
        let cal = Calendar.current
        let end = Date()
        let firstDay = LogicalDay.adding(-(range - 1), to: LogicalDay.of(end))
        let start = LogicalDay.range(firstDay).start
        let views = (try? model.contentStore?.views(from: start, to: end.addingTimeInterval(60))) ?? []
        let reasons = (try? model.contentStore?.reasons(from: start, to: end.addingTimeInterval(60))) ?? []
        let bars = dayBars(views: views, start: firstDay)
        let junkViews = views.filter { $0.isJunk(config: model.config) }

        PageScaffold(title: "趋势") {
            Picker("", selection: $range) {
                Text("近 7 天").tag(7)
                Text("近 30 天").tag(30)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 160)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Chart(bars) { b in
                        BarMark(x: .value("日期", b.day, unit: .day), y: .value("分钟", b.minutes))
                            .foregroundStyle(by: .value("类型", b.kind))
                    }
                    .chartForegroundStyleScale(["🥦 有营养": NutritionColor.good, "🍟 没营养": NutritionColor.junk])
                    .chartLegend(position: .top, alignment: .leading)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 5)) { v in
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { v in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel { if let m = v.as(Double.self) { Text("\(Int(m))′") } }
                        }
                    }
                    .frame(height: 220)

                    Grid(alignment: .topLeading, horizontalSpacing: 48, verticalSpacing: 28) {
                        GridRow {
                            ranking(title: "没营养的主题",
                                    items: tally(junkViews.compactMap { v in v.label.map { ($0.category, v.activeSeconds) } }))
                            ranking(title: "吸引你的钩子",
                                    items: tally(junkViews.compactMap { v in v.label?.hook.flatMap { $0 == "无" ? nil : ($0, v.activeSeconds) } }))
                        }
                        GridRow {
                            ranking(title: "最容易刷的时段", items: tally(junkViews.map { v in
                                let h = cal.component(.hour, from: Date(timeIntervalSince1970: v.startedAt))
                                return ("\(h):00–\(h + 1):00", v.activeSeconds)
                            }), limit: 3)
                            reasonList(reasons)
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 32)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }

    private func dayBars(views: [ContentView], start: Date) -> [DayBar] {
        let cal = Calendar.current
        var junk: [Date: Double] = [:], good: [Date: Double] = [:]
        for v in views {
            let d = LogicalDay.of(Date(timeIntervalSince1970: v.startedAt))
            if v.isJunk(config: model.config) { junk[d, default: 0] += v.activeSeconds } else { good[d, default: 0] += v.activeSeconds }
        }
        return (0..<range).flatMap { i -> [DayBar] in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return [DayBar(day: d, kind: "🥦 有营养", minutes: (good[d] ?? 0) / 60),
                    DayBar(day: d, kind: "🍟 没营养", minutes: (junk[d] ?? 0) / 60)]
        }
    }

    private func tally(_ pairs: [(String, Double)]) -> [(String, Double)] {
        Dictionary(pairs, uniquingKeysWith: +).sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func ranking(title: String, items: [(String, Double)], limit: Int = 5) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            if items.isEmpty { Text("还没有数据").font(.system(size: 13)).foregroundStyle(.tertiary) }
            ForEach(items.prefix(limit), id: \.0) { name, seconds in
                HStack {
                    Text(name).font(.system(size: 13))
                    Spacer()
                    Text(formatDuration(seconds)).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reasonList(_ reasons: [NudgeReason]) -> some View {
        let counts = Dictionary(grouping: reasons, by: \.reason).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            Text("你说的原因").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            if counts.isEmpty { Text("被提醒时点一下原因，这里会统计").font(.system(size: 13)).foregroundStyle(.tertiary) }
            ForEach(ReasonKind.allCases.filter { counts[$0] != nil }, id: \.self) { k in
                HStack {
                    Text(k.label).font(.system(size: 13))
                    Spacer()
                    Text("\(counts[k]!) 次").font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 报告

struct ReportsPage: View {
    @ObservedObject var model: MainModel
    @State private var selected: String?
    @State private var writing = false
    @State private var error: String?

    var body: some View {
        let _ = model.version
        let digests = (try? model.contentStore?.allDigests()) ?? []
        let current = digests.first { $0.day == selected } ?? digests.first

        PageScaffold(title: "报告") {
            HStack(spacing: 8) {
                Button(writing ? "正在写…" : "写今天的小结") { write(weekly: false) }.disabled(writing || !model.config.llm.enabled)
                Button("写本周复盘") { write(weekly: true) }.disabled(writing || !model.config.llm.enabled)
            }
        } content: {
            if digests.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有报告").font(.system(size: 15))
                    Text(model.config.llm.enabled ? "每晚 \(model.config.digestHour):00 写当天的小结，每周一写上一周的复盘。"
                         : "开启 AI 判断后，会自动写每日小结和每周复盘。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                }
                .padding(.horizontal, 32)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    List(digests, id: \.day, selection: Binding(get: { current?.day }, set: { selected = $0 })) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(d)).font(.system(size: 13, weight: .medium))
                            Text(d.daily?.headline ?? d.weekly?.headline ?? "旧格式").font(.system(size: 12))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 3)
                    }
                    .listStyle(.sidebar)
                    .frame(width: 240)
                    Divider()
                    ScrollView {
                        if let current { detail(current).padding(32).frame(maxWidth: 640, alignment: .leading) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func title(_ d: Digest) -> String {
        if d.day.contains("W") { return "\(d.day) 周复盘" }
        guard let date = DateFormatter.day.date(from: d.day) else { return d.day }
        return dayTitle(date) == "今天" || dayTitle(date) == "昨天" ? "\(dayTitle(date))的小结"
            : date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    @ViewBuilder
    private func detail(_ d: Digest) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title(d)).font(.system(size: 13)).foregroundStyle(.secondary)
            if let r = d.daily {
                Text(r.headline).font(.coach)
                bullets(r.findings)
                labeled("明天", r.tomorrow)
                SuggestionButton(suggestion: r.setting, model: model)
            } else if let r = d.weekly {
                Text(r.headline).font(.coach)
                if !r.patterns.isEmpty { section("规律") { bullets(r.patterns) } }
                if !r.cause.isEmpty { labeled("原因", r.cause) }
                if !r.actions.isEmpty { section("行动") { bullets(r.actions) } }
                if !r.alternative.isEmpty { labeled("有营养的替代", r.alternative) }
                labeled("下周承诺", r.commitment)
                SuggestionButton(suggestion: r.setting, model: model)
            } else {
                MarkdownBlock(text: d.text)
            }
            Text("\(d.model) 写于 \(Date(timeIntervalSince1970: d.createdAt).formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(.secondary).frame(width: 4, height: 4).offset(y: -3)
                    Text(t).font(.system(size: 15))
                }
            }
        }
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 15))
        }
    }

    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func write(weekly: Bool) {
        guard let writer = model.digestWriter else { return }
        writing = true
        error = nil
        let config = model.config
        Task {
            do {
                let d = weekly ? try await writer.writeWeekly(week: Week(containing: Date()), config: config)
                               : try await writer.write(day: Date(), config: config)
                selected = d.day
            } catch {
                self.error = "\(error)"
            }
            writing = false
            model.version += 1
        }
    }
}

extension DateFormatter {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// 旧格式（Markdown 长文）的报告：## 标题、- 列表、行内粗体
struct MarkdownBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                        .font(.headline).padding(.top, 6)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    Text("• " + line.dropFirst(2))
                } else if !line.isEmpty {
                    Text(inline(line))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

// MARK: - 删除确认

@MainActor
func confirmDeleteSite(_ site: String, model: MainModel) {
    let alert = NSAlert()
    alert.messageText = "删除 \(site) 的所有记录？"
    alert.informativeText = "所有日子里在这个网站上的浏览记录和时长都会删除，不能恢复。"
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    if alert.runModal() == .alertFirstButtonReturn { model.deleteSite(site) }
}

@MainActor
func confirmDeleteDay(_ day: Date, model: MainModel) {
    let alert = NSAlert()
    alert.messageText = "删除\(dayTitle(day))的全部记录？"
    alert.informativeText = "浏览记录、劝导记录、小结和时长都会删除，不能恢复。已经写进 Obsidian 的笔记不会删。"
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    if alert.runModal() == .alertFirstButtonReturn { model.deleteDay(day) }
}

/// 报告里的建议如果能用某个设置做到，就显示一个按钮，点一下生效
struct SuggestionButton: View {
    let suggestion: Suggestion?
    @ObservedObject var model: MainModel
    @State private var applied: String?

    var body: some View {
        if let applied {
            Label("已设置：\(applied)", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if let suggestion, let title = suggestion.title(for: model.config) {
            Button(title) {
                var config = model.settings.config
                suggestion.apply(to: &config)
                model.settings.config = config  // 触发保存并立即生效
                applied = title
            }
            .controlSize(.small)
        }
    }
}

// MARK: - 收藏

struct FavoritesPage: View {
    @ObservedObject var model: MainModel
    @State private var selected: Int64?

    var body: some View {
        let _ = model.version
        let items = (try? model.contentStore?.favorites()) ?? []
        let current = items.first { $0.id == selected } ?? items.first

        PageScaffold(title: "收藏", subtitle: items.isEmpty ? nil : "\(items.count) 条") {
            EmptyView()
        } content: {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有收藏").font(.system(size: 15))
                    Text("在浏览器里点扩展图标选“收藏这一页并提取要点”，或按 ⌥⇧S；也可以在“内容”页右键收藏看过的内容。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    List(items, selection: Binding(get: { current?.id }, set: { selected = $0 })) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(f.site)
                                switch f.status {
                                case .pending: Text("正在提取…")
                                case .failed: Text("提取失败").foregroundStyle(.orange)
                                case .done: if f.points?.worth == false { Text("不值得提炼") }
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(f.id)
                    }
                    .listStyle(.sidebar)
                    .frame(width: 260)
                    Divider()
                    ScrollView {
                        if let current { detail(current).padding(32).frame(maxWidth: 680, alignment: .leading) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ f: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(f.title).font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
                Text([f.site, f.author ?? "", "收藏于 \(Date(timeIntervalSince1970: f.savedAt).formatted(date: .abbreviated, time: .shortened))",
                      "根据\(f.textKind.label)提取"].filter { !$0.isEmpty }.joined(separator: "，"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            switch f.status {
            case .pending:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在提取要点…").foregroundStyle(.secondary) }
            case .failed:
                Text(f.error ?? "提取失败").font(.system(size: 13)).foregroundStyle(.orange)
            case .done:
                if let k = f.points, !k.worth {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("这一页没有值得留下的内容").font(.coachSmall)
                        Text(k.summary).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                } else if let k = f.points {
                    Text(k.summary).font(.coachSmall).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(k.points.enumerated()), id: \.offset) { _, p in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(.secondary).frame(width: 4, height: 4).offset(y: -3)
                                Text(p).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            if f.textKind == .none || f.textKind == .description {
                Text("只拿到了\(f.textKind == .none ? "标题" : "简介")，要点可能不完整。在浏览器打开这一页后用扩展收藏，能读到字幕或正文。")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                Button("在浏览器中打开") { if let u = URL(string: f.url) { NSWorkspace.shared.open(u) } }
                Button("重新提取") { model.favorites?.retry(f, config: model.config) }.disabled(f.status == .pending)
                Button("删除") {
                    try? model.contentStore?.deleteFavorite(id: f.id)
                    selected = nil
                    model.version += 1
                }
            }
            .controlSize(.small)
        }
    }
}

/// 收藏看过的内容；不能收藏（比如首页）时弹窗说明原因
@MainActor
func favoriteFromHistory(_ v: ContentView, model: MainModel) {
    guard let favorites = model.favorites else { return }
    let config = model.config
    Task {
        if let reason = await favorites.saveFromHistory(v, config: config) {
            let alert = NSAlert()
            alert.messageText = "不能收藏"
            alert.informativeText = reason
            alert.runModal()
        } else {
            model.page = .favorites
        }
    }
}
