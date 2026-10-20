import AppKit
import Charts
import SwiftUI
import FocusGuardCore

@MainActor
final class StatsModel: ObservableObject {
    @Published var stats: UsageStats
    @Published var config: Config
    var contentStore: ContentStore?
    var digestWriter: DigestWriter?
    @Published var mode: StatsMode = .timeline
    /// 删除某一天 / 某个网站的全部记录（由 AppDelegate 处理，同时清掉时长统计）
    var deleteDay: (Date) -> Void = { _ in }
    var deleteSite: (String) -> Void = { _ in }
    /// 有新的观看记录时 +1，让内容列表刷新
    @Published var contentVersion = 0

    init(stats: UsageStats, config: Config) {
        self.stats = stats
        self.config = config
    }
}

enum StatsMode: String, CaseIterable {
    case timeline = "时间线", time = "时长统计", content = "看过的内容", digest = "每日小结"
}

@MainActor
final class StatsWindow {
    let model: StatsModel
    private var window: NSWindow?

    init(model: StatsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: StatsView(model: model)))
            window.title = "专注守护 统计"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 开发用：画成 PNG
    static func renderPNG(model: StatsModel, junkOnly: Bool, to url: URL) {
        let view = NSHostingView(rootView: StatsView(model: model, junkOnly: junkOnly))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "不到 1 分钟" }
    if minutes < 60 { return "\(minutes) 分钟" }
    return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
}

struct StatsView: View {
    @ObservedObject var model: StatsModel
    @State var junkOnly = true
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var hoveredDay: Date?

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var totals: [DayTotal] { model.stats.junkTotals(days: 7, endingAt: Date(), config: model.config) }
    private var allItems: [UsageItem] { model.stats.items(on: selectedDay, config: model.config) }
    private var items: [UsageItem] { junkOnly ? allItems.filter(\.isJunk) : allItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $model.mode) {
                ForEach(StatsMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if model.mode == .timeline {
                dayNavigator
                TimelinePage(model: model, day: selectedDay)
            } else if model.mode == .content {
                dayNavigator
                ContentList(model: model, day: selectedDay)
            } else if model.mode == .digest {
                dayNavigator
                DigestPage(model: model, day: selectedDay)
            } else {
                weekChart
                Divider()
                dayHeader
                dayList
            }
        }
        .padding(20)
        .frame(width: 560, height: 680)
    }

    // MARK: 最近 7 天

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近 7 天 · 刷没营养内容的时长").font(.headline)
            let shown = hoveredDay ?? selectedDay
            let total = totals.first { $0.day == shown }?.seconds ?? 0
            Text("\(dayTitle(shown))：\(formatDuration(total))")
                .font(.callout).foregroundStyle(.secondary)

            Chart(totals) { t in
                BarMark(x: .value("日期", t.day, unit: .day), y: .value("分钟", t.seconds / 60), width: .ratio(0.55))
                    .foregroundStyle(Color.accentColor.opacity(t.day == selectedDay || t.day == hoveredDay ? 1 : 0.4))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) { Text(d == today ? "今天" : d.formatted(.dateTime.weekday(.abbreviated))) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))′") } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p): hoveredDay = day(at: p, proxy: proxy, geo: geo)
                            case .ended: hoveredDay = nil
                            }
                        }
                        .onTapGesture { p in
                            if let d = day(at: p, proxy: proxy, geo: geo) { selectedDay = d }
                        }
                }
            }
            .frame(height: 150)
            Text("点柱子查看那天的明细").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func day(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        let x = point.x - geo[proxy.plotAreaFrame].origin.x
        guard let d: Date = proxy.value(atX: x) else { return nil }
        let day = calendar.startOfDay(for: d)
        return totals.contains { $0.day == day } ? day : nil
    }

    // MARK: 某一天明细

    private var dayNavigator: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(selectedDay <= calendar.date(byAdding: .day, value: -29, to: today)!)
            Text(dayTitle(selectedDay)).font(.headline).frame(minWidth: 120)
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(selectedDay >= today)
        }
        .buttonStyle(.borderless)
    }

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                dayNavigator
                Spacer()
                Picker("", selection: $junkOnly) {
                    Text("没营养的").tag(true)
                    Text("全部").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            .buttonStyle(.borderless)
            let junk = allItems.filter(\.isJunk).reduce(0) { $0 + $1.seconds }
            let all = allItems.reduce(0) { $0 + $1.seconds }
            Text("没营养的内容 \(formatDuration(junk)) · 电脑总使用 \(formatDuration(all))")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var dayList: some View {
        let maxSeconds = items.first?.seconds ?? 1
        return Group {
            if items.isEmpty {
                VStack {
                    Spacer()
                    Text(junkOnly ? "这一天没有刷没营养的内容 👍" : "这一天没有记录")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            UsageRow(item: item, fraction: item.seconds / maxSeconds, showTag: !junkOnly)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        selectedDay = calendar.date(byAdding: .day, value: delta, to: selectedDay)!
    }

    private func dayTitle(_ day: Date) -> String {
        if day == today { return "今天" }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return "昨天" }
        return day.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}

private struct UsageRow: View {
    let item: UsageItem
    let fraction: Double
    let showTag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.isSite ? "globe" : "app")
                    .foregroundStyle(.secondary).frame(width: 16)
                Text(item.name).lineLimit(1)
                if showTag && item.isJunk {
                    Text("没营养")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().strokeBorder(.secondary))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDuration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(item.isJunk ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: max(4, geo.size.width * fraction))
            }
            .frame(height: 6)
            .padding(.leading, 22)
        }
    }
}

/// 某一天看过的视频 / 网页（来自浏览器扩展），以及劝导时记录的原因
private struct ContentList: View {
    @ObservedObject var model: StatsModel
    let day: Date

    private var range: (Date, Date) { (day, Calendar.current.date(byAdding: .day, value: 1, to: day)!) }
    private var views: [ContentView] {
        _ = model.contentVersion
        return (try? model.contentStore?.views(from: range.0, to: range.1)) ?? []
    }
    private var reasons: [NudgeReason] {
        (try? model.contentStore?.reasons(from: range.0, to: range.1)) ?? []
    }

    var body: some View {
        let views = self.views
        let reasons = self.reasons
        VStack(alignment: .leading, spacing: 10) {
            let total = views.reduce(0) { $0 + $1.activeSeconds }
            Text("\(views.count) 条 · 共 \(formatDuration(total))").font(.callout).foregroundStyle(.secondary)
            if !reasons.isEmpty {
                let counts = Dictionary(grouping: reasons, by: \.reason).mapValues(\.count)
                Text("你说刷的原因：" + ReasonKind.allCases.compactMap { k in counts[k].map { "\(k.label) ×\($0)" } }.joined(separator: "  "))
                    .font(.callout)
            }
            if views.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("这一天没有内容记录").foregroundStyle(.secondary)
                    Text("需要先安装 Chrome 扩展：菜单 → 设置… → 内容记录").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(views, id: \.viewId) { v in
                    ContentRow(view: v).contextMenu {
                        Button("删除 \(v.site) 的所有记录…") { confirmDeleteSite(v.site, model: model) }
                    }
                }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

private struct ContentRow: View {
    let view: ContentView

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Date(timeIntervalSince1970: view.startedAt).formatted(date: .omitted, time: .shortened))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(view.title.isEmpty ? view.url : view.title).lineLimit(2)
                Text([view.site, view.author].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !view.tags.isEmpty {
                    Text(view.tags.prefix(6).map { "#" + $0 }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                if let label = view.label {
                    let hook = label.hook.flatMap { $0 == "无" ? nil : " · 钩子：\($0)" } ?? ""
                    Text("\(label.isJunk ? "🍟 没营养" : "🥦 有营养") \(label.nutrition)/5 · \(label.category)\(hook) · \(label.reason)")
                        .font(.caption).lineLimit(2)
                        .help("由 \(label.model) 判断")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(view.activeSeconds < 60 ? "\(Int(view.activeSeconds)) 秒" : formatDuration(view.activeSeconds)).monospacedDigit()
                if let d = view.mediaDuration, d > 0, view.kind == "video" {
                    Text("看了 \(min(100, Int(view.watchedSeconds / d * 100)))%").font(.caption).foregroundStyle(.secondary)
                }
                if view.backgroundSeconds >= 1 {
                    Text("后台播放 \(view.backgroundSeconds < 60 ? "\(Int(view.backgroundSeconds)) 秒" : formatDuration(view.backgroundSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 每日小结 / 每周复盘：显示大模型写的内容，可以手动写或重写
private struct DigestPage: View {
    @ObservedObject var model: StatsModel
    let day: Date
    @State private var weekly = false
    @State private var writing = false
    @State private var error: String?

    var body: some View {
        let _ = model.contentVersion
        let week = Week(containing: day)
        let digest = weekly ? model.digestWriter?.weekly(for: week) : model.digestWriter?.digest(for: day)
        VStack(alignment: .leading, spacing: 12) {
            if !model.config.llm.enabled || model.digestWriter == nil {
                Spacer()
                Text("需要先在“设置… → AI 判断”里开启大模型").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack {
                    Picker("", selection: $weekly) {
                        Text("当天小结").tag(false)
                        Text("这一周的复盘（\(week.key)）").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                    Spacer()
                    Button(writing ? "正在写…" : (digest == nil ? "现在就写" : "重新写")) { write(week: week) }
                        .disabled(writing)
                }
                Group {
                    if let digest {
                        Text("由 \(digest.model) 写于 \(Date(timeIntervalSince1970: digest.createdAt).formatted(date: .abbreviated, time: .shortened))")
                    } else if weekly {
                        Text("每周一自动写上一周的复盘")
                    } else {
                        Text("每天 \(model.config.digestHour):00 自动写当天的小结")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let error { Text("⚠️ \(error)").font(.callout).foregroundStyle(.orange) }
                if let digest {
                    ScrollView { MarkdownBlock(text: digest.text).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    Spacer()
                }
            }
        }
    }

    private func write(week: Week) {
        guard let writer = model.digestWriter else { return }
        writing = true
        error = nil
        let config = model.config
        let weekly = self.weekly
        Task {
            do {
                if weekly { try await writer.writeWeekly(week: week, config: config) }
                else { try await writer.write(day: day, config: config) }
            } catch {
                self.error = "\(error)"
            }
            writing = false
        }
    }
}

/// 简单的 Markdown 显示：## 标题、- 列表、行内粗体
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
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

/// 有营养 / 没营养的颜色（色盲友好的蓝 / 橙，分别适配浅色和深色）
enum NutritionColor {
    static let good = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x39 / 255, green: 0x87 / 255, blue: 0xe5 / 255, alpha: 1)
        : NSColor(srgbRed: 0x2a / 255, green: 0x78 / 255, blue: 0xd6 / 255, alpha: 1) })
    static let junk = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0xd9 / 255, green: 0x59 / 255, blue: 0x26 / 255, alpha: 1)
        : NSColor(srgbRed: 0xeb / 255, green: 0x68 / 255, blue: 0x34 / 255, alpha: 1) })
}

@MainActor
func confirmDeleteSite(_ site: String, model: StatsModel) {
    let alert = NSAlert()
    alert.messageText = "删除 \(site) 的所有记录？"
    alert.informativeText = "所有日子里在这个网站上的观看记录和时长统计都会删除，不能恢复。"
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    alert.buttons.first?.hasDestructiveAction = true
    if alert.runModal() == .alertFirstButtonReturn { model.deleteSite(site) }
}

/// 时间线：一天 24 小时的分布 + 按时间排列的浏览段落
private struct TimelinePage: View {
    @ObservedObject var model: StatsModel
    let day: Date
    @State private var hovered: Int?
    @State private var expanded: Set<String> = []

    var body: some View {
        let _ = model.contentVersion
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let views = (try? model.contentStore?.views(from: day, to: end)) ?? []
        let timeline = Timeline.build(views: views, config: model.config)
        let junk = timeline.sessions.reduce(0) { $0 + $1.junkSeconds }
        let total = timeline.sessions.reduce(0) { $0 + $1.activeSeconds }

        VStack(alignment: .leading, spacing: 10) {
            if views.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("这一天没有浏览记录").foregroundStyle(.secondary)
                    Text("想看到所有网页的时间线：设置… → 内容记录 → 记录所有网页").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                hourChart(timeline.hours)
                Text(summary(hovered.map { timeline.hours[$0] }, junk: junk, total: total, count: timeline.sessions.count))
                    .font(.callout).foregroundStyle(.secondary)
                List {
                    ForEach(timeline.sessions) { session in
                        sessionRow(session)
                            .contextMenu {
                                Button("删除 \(session.site) 的所有记录…") { confirmDeleteSite(session.site, model: model) }
                            }
                    }
                }
                .listStyle(.inset)
                HStack {
                    Spacer()
                    Button("删除这一天的全部记录…", role: .destructive) { confirmDeleteDay() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private func hourChart(_ hours: [HourBucket]) -> some View {
        Chart {
            ForEach(hours) { h in
                BarMark(x: .value("小时", Double(h.hour)), y: .value("分钟", h.goodSeconds / 60), width: 10)
                    .foregroundStyle(by: .value("类型", "🥦 有营养"))
                BarMark(x: .value("小时", Double(h.hour)), y: .value("分钟", h.junkSeconds / 60), width: 10)
                    .foregroundStyle(by: .value("类型", "🍟 没营养"))
            }
            if let hovered {
                RuleMark(x: .value("小时", Double(hovered))).foregroundStyle(.quaternary)
            }
        }
        .chartForegroundStyleScale(["🥦 有营养": NutritionColor.good, "🍟 没营养": NutritionColor.junk])
        .chartLegend(position: .top, alignment: .leading)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18]) { v in
                AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h)) 点") } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let m = v.as(Double.self) { Text("\(Int(m))′") } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let x = p.x - geo[proxy.plotAreaFrame].origin.x
                            if let h: Double = proxy.value(atX: x) { hovered = min(23, max(0, Int(h.rounded()))) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: 130)
    }

    private func summary(_ hour: HourBucket?, junk: Double, total: Double, count: Int) -> String {
        if let h = hour {
            return "\(h.hour) 点：没营养 \(formatDuration(h.junkSeconds))，有营养 \(formatDuration(h.goodSeconds))"
        }
        return "\(count) 段 · 没营养 \(formatDuration(junk)) · 有营养 \(formatDuration(total - junk))"
    }

    private func sessionRow(_ s: TimelineSession) -> some View {
        let isOpen = expanded.contains(s.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Text(timeRange(s)).monospacedDigit().foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                RoundedRectangle(cornerRadius: 2)
                    .fill(s.isJunk ? NutritionColor.junk : NutritionColor.good)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.isJunk ? "🍟" : "🥦")
                        Text(s.site).bold()
                        Text(s.items.count > 1 ? "\(s.items.count) 条 · \(formatDuration(s.activeSeconds))" : formatDuration(s.activeSeconds))
                            .foregroundStyle(.secondary)
                    }
                    Text(s.items.prefix(isOpen ? s.items.count : 2).map(\.title).joined(separator: isOpen ? "\n" : " / "))
                        .font(.callout).lineLimit(isOpen ? nil : 1).foregroundStyle(.secondary)
                }
                Spacer()
                if s.items.count > 2 {
                    Button(isOpen ? "收起" : "展开") {
                        if isOpen { expanded.remove(s.id) } else { expanded.insert(s.id) }
                    }
                    .buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func timeRange(_ s: TimelineSession) -> String {
        let f = { (t: Double) -> String in
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
            return String(format: "%02d:%02d", c.hour!, c.minute!)
        }
        return f(s.start) == f(s.end) ? f(s.start) : "\(f(s.start))–\(f(s.end))"
    }

    private func confirmDeleteDay() {
        let alert = NSAlert()
        alert.messageText = "删除这一天的全部记录？"
        alert.informativeText = "看过的内容、劝导记录、小结和时长统计都会删除，不能恢复。（已经写进 Obsidian 的笔记不会删）"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { model.deleteDay(day) }
    }
}
