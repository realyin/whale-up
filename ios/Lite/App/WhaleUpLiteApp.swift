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
    @State private var showSetup = false
    @Environment(\.scenePhase) private var phase
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var line: String {
        if usage.isOver { return "今天刷够了哦！\n先放下手机，明天凌晨 \(usage.dayStartHour) 点再见～" }
        if usage.used == 0 { return "今天还没刷，真棒～\n每天 \(usage.limit + usage.extra) 分钟，用完我就拦着你。" }
        return "今天刷了 \(formatMinutes(usage.used))，还能刷 \(formatMinutes(usage.leftSeconds))。"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(line)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.paper))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.ink, lineWidth: 2.5))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).padding(5))
                    // 刷够了抱着抱枕睡觉，平时喝着奶茶陪你
                    // 她的图是包里的普通 PNG（不在素材目录里），要用 UIImage 读
                    Image(uiImage: UIImage(named: usage.isOver ? "pose-sleep_curl" : "pose-milktea") ?? UIImage())
                        .resizable().scaledToFit().frame(height: 210)
                        .scaleEffect(x: breathe ? 1.006 : 1, y: breathe ? 1.02 : 1, anchor: .bottom)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathe)
                        .onAppear { breathe = true }
                }

                card("今天") {
                    let apps = Set(usage.seconds.keys).union(usage.open.keys).sorted { usage.usedSeconds($0) > usage.usedSeconds($1) }
                    ProgressView(value: min(1, usage.used / max(1, usage.limitSeconds)))
                        .tint(usage.isOver ? Theme.junk : Theme.accent)
                    if apps.isEmpty {
                        Text("还没有记录。按下面的步骤设好快捷指令，打开抖音时就会开始计时。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(apps, id: \.self) { app in
                        HStack {
                            Text(app).font(.subheadline.weight(.semibold))
                            if usage.open[app] != nil { Text("正在刷").font(.caption2.bold()).foregroundColor(Theme.junk) }
                            Spacer()
                            Text(formatMinutes(usage.usedSeconds(app))).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }

                card("每天一共能刷") {
                    Stepper(value: Binding(get: { usage.limit }, set: { usage.limit = $0; usage.save() }), in: 5...240, step: 5) {
                        Text("\(usage.limit) 分钟").font(.system(.title3, design: .rounded).bold())
                    }
                    Text("抖音等 App 和 Safari 分开算：Safari 里的时长在 Safari 扩展的面板里设。")
                        .font(.footnote).foregroundColor(.secondary)
                }

                card("今天再多看") {
                    HStack(spacing: 10) {
                        ForEach([5, 10, 30], id: \.self) { m in
                            Button("\(m) 分钟") {
                                usage.extra += m
                                usage.save()
                            }
                            .buttonStyle(Pill(small: true))
                        }
                    }
                    Text(usage.extra > 0 ? "今天已经多加了 \(usage.extra) 分钟，用完还会拦着你。" : "真想多看才点。只管今天，用完还会拦着你。")
                        .font(.footnote).foregroundColor(.secondary)
                }

                card("怎么设置") {
                    DisclosureGroup(isExpanded: $showSetup) {
                        SetupGuide().padding(.top, 8)
                    } label: {
                        Text("两步：快捷指令自动化 + Safari 扩展").font(.subheadline).foregroundColor(Theme.ink)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.soft.ignoresSafeArea())
        .onReceive(ticker) { _ in usage = Usage.load() }
        .onChange(of: phase) { _, p in if p == .active { usage = Usage.load() } }
        .task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundColor(Theme.ink)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.ink, lineWidth: 2))
    }
}

/// 设置步骤
struct SetupGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("① 抖音等 App：快捷指令自动化").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 6) {
                step("打开“快捷指令” → 底部“自动化” → 右上角 ＋ → “App”")
                step("选抖音（可以多选：快手、小红书、B 站……），勾“已打开”，选“立即运行”")
                step("下一步里选 App“鲸醒”的动作“开始刷”，App 名字填“抖音”")
                step("再建一个：同样选这些 App，勾“已关闭”，动作选“刷完了”")
            }
            Button("打开快捷指令") { UIApplication.shared.open(URL(string: "shortcuts://")!) }.buttonStyle(Pill(small: true))

            Text("② Safari 里刷视频：Safari 扩展").font(.subheadline.bold()).padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                step("打开“设置” → “App” → “Safari 浏览器” → “扩展”")
                step("打开“鲸醒”，网站权限选“允许”")
                step("在 Safari 地址栏点扩展图标，就能看到今天刷了多久、设时长")
            }
        }
        .foregroundColor(Theme.ink)
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text).font(.footnote)
        }
    }
}

/// 女仆装风格的按钮
struct Pill: ButtonStyle {
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(small ? .subheadline : .headline, design: .rounded).weight(.bold))
            .foregroundColor(small ? Theme.ink : .white)
            .padding(.horizontal, small ? 14 : 20).padding(.vertical, small ? 8 : 14)
            // 阴影只给底下的胶囊，不然字也会带一道重影
            .background(Capsule().fill(small ? Theme.soft : Theme.accent)
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
                .shadow(color: Theme.ink, radius: 0, y: configuration.isPressed ? 0 : 3))
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}
