import AppKit
import Charts
import SwiftUI
import FocusGuardCore

@MainActor
final class StatsModel: ObservableObject {
    @Published var stats: UsageStats
    @Published var config: Config
    var contentStore: ContentStore?
    /// 有新的观看记录时 +1，让内容列表刷新
    @Published var contentVersion = 0

    init(stats: UsageStats, config: Config) {
        self.stats = stats
        self.config = config
    }
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
    @State private var showContent = false

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var totals: [DayTotal] { model.stats.junkTotals(days: 7, endingAt: Date(), config: model.config) }
    private var allItems: [UsageItem] { model.stats.items(on: selectedDay, config: model.config) }
    private var items: [UsageItem] { junkOnly ? allItems.filter(\.isJunk) : allItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $showContent) {
                Text("时长统计").tag(false)
                Text("看过的内容").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            if showContent {
                dayNavigator
                ContentList(model: model, day: selectedDay)
            } else {
                weekChart
                Divider()
                dayHeader
                dayList
            }
        }
        .padding(20)
        .frame(width: 520, height: 640)
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
                List(views, id: \.viewId) { v in ContentRow(view: v) }
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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(view.activeSeconds < 60 ? "\(Int(view.activeSeconds)) 秒" : formatDuration(view.activeSeconds)).monospacedDigit()
                if let d = view.mediaDuration, d > 0, view.kind == "video" {
                    Text("看了 \(min(100, Int(view.watchedSeconds / d * 100)))%").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
