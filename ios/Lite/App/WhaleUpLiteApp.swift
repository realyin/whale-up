import AppIntents
import SwiftUI
import UserNotifications

// 免费版：抖音这类 App 靠“快捷指令”的个人自动化计时——打开 App 时运行“开始刷”，关掉时运行“刷完了”。
// 今天刷够了以后再打开，“开始刷”会直接把鲸醒叫到前台，大肥鱼拦着你。

@main
struct WhaleUpLiteApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

// MARK: - 用量

/// 今天每个 App 刷了多久；存在 App 自己的设置里
struct Usage: Codable {
    var limit = 30
    var dayStartHour = 4
    var day = ""
    var seconds: [String: Double] = [:]
    /// 正在刷的 App 和开始时间（还没收到“刷完了”）
    var open: [String: Date] = [:]
    var extraDay = ""
    var extra = 0

    /// 一次最多算 2 小时：手机重启、自动化没跑等情况下，不会一直算下去
    static let maxSession: Double = 2 * 3600
    private static let key = "usage"

    static func load() -> Usage {
        // 开发用：用 -demo 启动时给一份示例数据，截图看界面
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            var d = Usage()
            d.day = d.dayKey(); d.extraDay = d.day
            d.seconds = ["抖音": 14 * 60, "小红书": 5 * 60]
            d.open = ["B 站": Date().addingTimeInterval(-3 * 60)]
            return d
        }
        var u = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Usage.self, from: $0) } ?? Usage()
        let today = u.dayKey()
        if u.day != today {
            u.day = today
            u.seconds = [:]
            u.open = [:]
        }
        if u.extraDay != today { u.extraDay = today; u.extra = 0 }
        return u
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// 凌晨 dayStartHour 点以前算前一天
    func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-Double(dayStartHour) * 3600))
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func usedSeconds(_ app: String, now: Date = Date()) -> Double {
        (seconds[app] ?? 0) + (open[app].map { min(Self.maxSession, now.timeIntervalSince($0)) } ?? 0)
    }

    var used: Double {
        Set(seconds.keys).union(open.keys).reduce(0) { $0 + usedSeconds($1) }
    }

    var limitSeconds: Double { Double(limit + extra) * 60 }
    var isOver: Bool { used >= limitSeconds }
    var leftSeconds: Double { max(0, limitSeconds - used) }

    mutating func start(_ app: String) {
        stop(app)
        open[app] = Date()
    }

    mutating func stop(_ app: String) {
        guard let started = open.removeValue(forKey: app) else { return }
        seconds[app, default: 0] += min(Self.maxSession, Date().timeIntervalSince(started))
    }
}

// MARK: - 提醒

enum Whisper {
    static let ids = ["whaleup.warn", "whaleup.over"]

    /// 按今天剩下的时间排两条通知：还剩 5 分钟、时间到
    static func schedule(left: Double, limitMinutes: Int, startHour: Int) {
        cancel()
        func add(_ id: String, after: Double, _ title: String, _ body: String) {
            guard after > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        add("whaleup.warn", after: left - 300, "大肥鱼盯着你呢", "今天的 \(limitMinutes) 分钟只剩 5 分钟了哦。")
        add("whaleup.over", after: left, "看我的魔法！", "今天刷够了，快关掉吧。再打开我会拦着你的～明天凌晨 \(startHour) 点再见。")
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - 快捷指令里的两个动作

struct StartIntent: AppIntent, ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "开始刷"
    static var description = IntentDescription("打开抖音等 App 时运行：鲸醒开始计时。今天刷够了，就跳回鲸醒，大肥鱼拦着你。")
    static var openAppWhenRun = false

    @Parameter(title: "App", default: "抖音")
    var app: String

    @MainActor
    func perform() async throws -> some IntentResult {
        var u = Usage.load()
        if u.isOver {
            u.save()
            throw needsToContinueInForegroundError("今天刷够了，大肥鱼把你带回来了。")
        }
        u.start(app)
        u.save()
        Whisper.schedule(left: u.leftSeconds, limitMinutes: u.limit + u.extra, startHour: u.dayStartHour)
        return .result()
    }
}

struct StopIntent: AppIntent {
    static var title: LocalizedStringResource = "刷完了"
    static var description = IntentDescription("关掉抖音等 App 时运行：鲸醒停止计时。")
    static var openAppWhenRun = false

    @Parameter(title: "App", default: "抖音")
    var app: String

    @MainActor
    func perform() async throws -> some IntentResult {
        var u = Usage.load()
        u.stop(app)
        u.save()
        if u.open.isEmpty { Whisper.cancel() }
        return .result()
    }
}

struct WhaleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartIntent(), phrases: ["用\(.applicationName)开始计时"], shortTitle: "开始刷", systemImageName: "play.circle")
        AppShortcut(intent: StopIntent(), phrases: ["用\(.applicationName)停止计时"], shortTitle: "刷完了", systemImageName: "stop.circle")
    }
}

// MARK: - 主页

struct HomeView: View {
    @State private var usage = Usage.load()
    @State private var breathe = false
    @Environment(\.scenePhase) private var phase
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var line: String {
        if usage.isOver { return "今天刷够了哦！先放下手机～\n明天凌晨 \(usage.dayStartHour) 点再见。" }
        if usage.used < 60 { return "今天还没刷，真棒～\n每天 \(usage.limit + usage.extra) 分钟，用完我就拦着你。" }
        if usage.leftSeconds <= 300 { return "只剩 \(formatMinutes(usage.leftSeconds)) 了，\n看完这个就停吧！" }
        return "我盯着你呢。\n今天还能刷 \(formatMinutes(usage.leftSeconds))。"
    }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    hero
                    todayCard
                    limitCard
                    extraCard
                    SetupCard()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        // 自己的配色，不跟系统深色模式变
        .preferredColorScheme(.light)
        .onReceive(ticker) { _ in usage = Usage.load() }
        .onChange(of: phase) { _, p in if p == .active { usage = Usage.load() } }
        .task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("鲸醒").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink)
            Text("WhaleUp").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(Theme.accent)
            Spacer()
        }
        .padding(.top, 6)
    }

    /// 大肥鱼和她的气泡：刷够了抱着抱枕睡觉，平时喝着奶茶陪你
    private var hero: some View {
        VStack(spacing: 2) {
            SpeechBubble(text: line)
            Image(uiImage: UIImage(named: usage.isOver ? "pose-sleep_curl" : "pose-milktea") ?? UIImage())
                .resizable().scaledToFit().frame(height: 200)
                .scaleEffect(x: breathe ? 1.006 : 1, y: breathe ? 1.02 : 1, anchor: .bottom)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathe)
                .onAppear { breathe = true }
        }
    }

    private var todayCard: some View {
        CardBox(title: "今天", icon: "chart.pie.fill") {
            HStack(spacing: 20) {
                UsageRing(used: usage.used, total: usage.limitSeconds)
                VStack(alignment: .leading, spacing: 6) {
                    Text(usage.isOver ? "今天用完啦" : "还能刷")
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                    Text(usage.isOver ? "明天见" : formatMinutes(usage.leftSeconds))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(usage.isOver ? Theme.junk : Theme.ink)
                    if usage.extra > 0 {
                        Text("含今天多加的 \(usage.extra) 分钟")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.soft))
                    }
                }
                Spacer(minLength: 0)
            }
            let apps = Set(usage.seconds.keys).union(usage.open.keys).sorted { usage.usedSeconds($0) > usage.usedSeconds($1) }
            if apps.isEmpty {
                Text("还没有记录。按下面“怎么设置”设好快捷指令，打开抖音时就会开始计时。")
                    .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
            } else {
                Divider().overlay(Theme.track)
                ForEach(apps, id: \.self) { app in
                    HStack(spacing: 8) {
                        Text(app).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.ink)
                        if usage.open[app] != nil {
                            Text("正在刷").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.junk))
                        }
                        Spacer()
                        Text(formatMinutes(usage.usedSeconds(app)))
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                    }
                }
            }
        }
    }

    private var limitCard: some View {
        CardBox(title: "每天一共能刷", icon: "hourglass") {
            HStack {
                RoundButton(symbol: "minus") { setLimit(usage.limit - 5) }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(usage.limit)").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink)
                    Text("分钟").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(Theme.muted)
                }
                Spacer()
                RoundButton(symbol: "plus") { setLimit(usage.limit + 5) }
            }
            Text("抖音等 App 在这里算；Safari 里刷视频的时长在 Safari 扩展的面板里设。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
        }
    }

    private var extraCard: some View {
        CardBox(title: "今天再多看", icon: "plus.circle.fill") {
            HStack(spacing: 10) {
                ForEach([5, 10, 30], id: \.self) { m in
                    Button("+\(m) 分钟") {
                        usage.extra += m
                        usage.save()
                    }
                    .buttonStyle(Pill(small: true))
                }
            }
            Text("真想多看才点。只管今天，用完还会拦着你。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
        }
    }

    private func setLimit(_ value: Int) {
        usage.limit = min(240, max(5, value))
        usage.save()
    }
}

/// 圆形的 − / ＋ 按钮
struct RoundButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.soft))
                .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// 设置步骤：编号圆点 + 一句话
struct SetupCard: View {
    @State private var open = false

    var body: some View {
        CardBox(title: "怎么设置", icon: "wand.and.stars") {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text("两步：快捷指令自动化 + Safari 扩展")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if open {
                section("抖音等 App", icon: "app.badge.fill", steps: [
                    "打开“快捷指令”，点底部“自动化”，再点右上角 ＋，选“App”",
                    "选抖音（可以多选快手、小红书、B 站），勾“已打开”，选“立即运行”",
                    "动作选 App“鲸醒”里的“开始刷”，App 名字填“抖音”",
                    "再建一个：同样的 App，勾“已关闭”，动作选“刷完了”",
                ])
                Button("打开快捷指令") { UIApplication.shared.open(URL(string: "shortcuts://")!) }
                    .buttonStyle(Pill(small: true))
                section("Safari 里刷视频", icon: "safari.fill", steps: [
                    "打开“设置” → “App” → “Safari 浏览器” → “扩展”",
                    "打开“鲸醒”，网站权限选“允许”",
                    "在 Safari 地址栏点扩展图标，看今天刷了多久、设每天的时长",
                ])
            }
        }
    }

    private func section(_ title: String, icon: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(Theme.accent))
                    Text(text).font(.system(size: 14, design: .rounded)).foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }
}

/// 女仆装风格的按钮：深蓝描边、底下一道实色阴影
struct Pill: ButtonStyle {
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 15 : 17, weight: .bold, design: .rounded))
            .foregroundColor(small ? Theme.ink : .white)
            .padding(.horizontal, small ? 14 : 20).padding(.vertical, small ? 9 : 14)
            .background(Capsule().fill(small ? Theme.soft : Theme.accent)
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
                .shadow(color: Theme.ink, radius: 0, y: configuration.isPressed ? 0 : 3))
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}
