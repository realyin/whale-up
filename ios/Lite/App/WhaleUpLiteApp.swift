import AppIntents
import SwiftUI
import UserNotifications

// 免费版：抖音这类 App 靠“快捷指令”的个人自动化计时——打开 App 时运行“开始刷”，关掉时运行“刷完了”。
// 今天刷够了以后再打开，“开始刷”会直接把鲸醒叫到前台，大肥鱼拦着你。
// Safari 里刷视频由 Safari 扩展计时，和 App 共用同一份设置和今天的总时长（存在 App Group 里，见 Usage.swift）。

@main
struct WhaleUpLiteApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
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
        Whisper.schedule(left: u.leftSeconds, limitMinutes: u.todayLimit, startHour: u.dayStartHour)
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
    /// 正在等输随机码的放松操作
    @State private var gate: CodeRequest?
    @Environment(\.scenePhase) private var phase
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var line: String {
        if usage.isOver { return "今天刷够了哦！先放下手机～\n明天凌晨 \(usage.dayStartHour) 点再见。" }
        if usage.used < 60 { return "今天还没刷，真棒～\n今天 \(usage.todayLimit) 分钟，用完我就拦着你。" }
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
                    adjustCard
                    sitesCard
                    AICard()
                    SetupCard()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        // 自己的配色，不跟系统深色模式变
        .preferredColorScheme(.light)
        .sheet(item: $gate) { req in
            CodeSheet(request: req) { gate = nil }
        }
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
                    if usage.extra != 0 {
                        Text(usage.extra > 0 ? "含今天多加的 \(usage.extra) 分钟" : "今天少看了 \(-usage.extra) 分钟")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.soft))
                    }
                }
                Spacer(minLength: 0)
            }
            let apps = Set(usage.seconds.keys).union(usage.open.keys).sorted { usage.usedSeconds($0) > usage.usedSeconds($1) }
            let goodTotal = usage.good.values.reduce(0, +)
            if apps.isEmpty {
                Text("还没有记录。按下面“怎么设置”设好快捷指令，打开抖音时就会开始计时。")
                    .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
            } else {
                Divider().overlay(Theme.track)
                if goodTotal >= 60 {
                    HStack {
                        Text("有营养的（不算时间）").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.accent)
                        Spacer()
                        Text(formatMinutes(goodTotal)).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.accent)
                    }
                }
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
                RoundButton(symbol: "plus") {
                    // 调大每天的时长要先输随机码
                    gate = CodeRequest(what: "每天从 \(usage.limit) 分钟调到 \(min(240, usage.limit + 5)) 分钟") { setLimit(usage.limit + 5) }
                }
            }
            Text("抖音等 App 和 Safari 里刷视频一起算，Safari 扩展的面板里改的也是这一个。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
        }
    }

    /// 今天多看 / 少看：每次 5 分钟，只管今天，明天凌晨 4 点归零
    private var adjustCard: some View {
        CardBox(title: "今天多看 / 少看", icon: "plusminus.circle.fill") {
            HStack {
                RoundButton(symbol: "minus") { adjust(-5) }
                    .opacity(usage.limit + usage.extra <= 5 ? 0.35 : 1)
                Spacer()
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(usage.extra == 0 ? "±0" : usage.extra > 0 ? "+\(usage.extra)" : "−\(-usage.extra)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(usage.extra > 0 ? Theme.junk : usage.extra < 0 ? Theme.accent : Theme.ink)
                        Text("分钟").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(Theme.muted)
                    }
                    Text("今天一共 \(usage.todayLimit) 分钟")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                }
                Spacer()
                RoundButton(symbol: "plus") {
                    // 多看：每天最多 2 次，还要输随机码
                    if usage.grantsLeft > 0 {
                        gate = CodeRequest(what: "今天多看 5 分钟（今天还能多看 \(usage.grantsLeft) 次）") { adjust(5) }
                    }
                }
                .opacity(usage.grantsLeft == 0 ? 0.35 : 1)
            }
            Text("只管今天，明天凌晨 \(usage.dayStartHour) 点自动归零。少看随时可以；多看要输一串随机码，每天最多 \(Usage.maxGrants) 次（今天还剩 \(usage.grantsLeft) 次）。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
            if usage.extra < 0 {
                // 少看了：恢复等于放松，也要输随机码（多看的恢复是收紧，随时可以）
                Button("恢复成每天的 \(usage.limit) 分钟") {
                    gate = CodeRequest(what: "恢复成每天的 \(usage.limit) 分钟") { usage.extra = 0; usage.save() }
                }
                    .buttonStyle(Pill(small: true))
            } else if usage.extra > 0 {
                Button("恢复成每天的 \(usage.limit) 分钟") { usage.extra = 0; usage.save() }
                    .buttonStyle(Pill(small: true))
            }
        }
    }

    private func adjust(_ minutes: Int) {
        usage.adjust(minutes)
        usage.save()
        // 正在刷：按新的时间重新排提醒
        if !usage.open.isEmpty {
            Whisper.schedule(left: usage.leftSeconds, limitMinutes: usage.todayLimit, startHour: usage.dayStartHour)
        }
    }

    @State private var newSite = ""
    @State private var siteError: String?

    /// 要管的网站：Safari 扩展按这个名单计时、锁；加随时可以，删要输随机码
    private var sitesCard: some View {
        CardBox(title: "要管的网站", icon: "globe") {
            VStack(spacing: 0) {
                ForEach(usage.sites, id: \.self) { site in
                    HStack {
                        Text(site).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.ink)
                        Spacer()
                        Button {
                            gate = CodeRequest(what: "从名单里删掉 \(site)") {
                                usage.sites.removeAll { $0 == site }
                                usage.save()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundColor(Theme.muted.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 9)
                    if site != usage.sites.last { Divider().overlay(Theme.track) }
                }
            }
            HStack(spacing: 10) {
                TextField("输入网址或域名，如 douyin.com", text: $newSite)
                    .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.soft))
                    .onSubmit(addSite)
                Button("添加", action: addSite).buttonStyle(Pill(small: true))
            }
            if let siteError {
                Text(siteError).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.junk)
            }
            Text("Safari 里打开这些网站时，大肥鱼就会出来计时，到点锁上。加网站随时生效，删网站要输随机码。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
        }
    }

    /// 从输入里取出域名：去掉 http(s)://、www.、路径
    private func addSite() {
        var s = newSite.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        s = String(s.split(separator: "/").first ?? "")
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasPrefix("m.") { s.removeFirst(2) }
        guard s.contains("."), !s.contains(" ") else { siteError = "这看起来不像网址，试试 douyin.com 这样的"; return }
        guard !usage.sites.contains(s) else { siteError = "\(s) 已经在名单里了"; return }
        usage.sites.append(s)
        usage.save()
        newSite = ""
        siteError = nil
    }

    private func setLimit(_ value: Int) {
        usage.setLimit(value)
        usage.save()
    }
}

/// AI 判断有没有营养：DeepSeek 的 Key、你的标准、测试一下
struct AICard: View {
    @State private var settings = AISettings.load()
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        CardBox(title: "AI 判断有没有营养", icon: "sparkles") {
            Toggle(isOn: $settings.enabled) {
                Text("开启（Safari 里的视频）").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.ink)
            }
            .tint(Theme.accent)
            if settings.enabled {
                field("DeepSeek API Key") {
                    SecureField("sk-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("你的标准").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                    TextEditor(text: $settings.preferences)
                        .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.soft))
                }
                HStack(spacing: 12) {
                    Button("测试一下") { test() }.buttonStyle(Pill(small: true)).disabled(testing || !settings.ready)
                    if testing { ProgressView() }
                }
                if let result {
                    Text(result).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(result.hasPrefix("✓") ? Theme.accent : Theme.junk)
                }
            }
            Text("开启后，Safari 里看的视频会把标题、作者、简介发给 DeepSeek 判断：有营养的不计时，没营养的照常计时、到点锁上。同一个视频只问一次。抖音等 App 里看不到内容，只能按时长算。")
                .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.muted)
        }
        .onChange(of: settings) { _, s in s.save() }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
            content()
                .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.soft))
        }
    }

    /// 拿两条示例问一下，看 Key 和标准管不管用
    private func test() {
        testing = true
        result = nil
        Task {
            do {
                let good = try await Judge.ask(["site": "bilibili.com", "title": "【入门】Swift 并发编程，30 分钟讲清楚", "author": "程序员小王"], settings: settings)
                let junk = try await Judge.ask(["site": "douyin.com", "title": "猫猫翻车合集 第 47 集 #萌宠 #搞笑"], settings: settings)
                result = "✓ 能用了。Swift 教程：\(good.isJunk ? "没营养" : "有营养")；猫猫翻车：\(junk.isJunk ? "没营养" : "有营养")"
            } catch {
                result = "没成功：\(error)"
            }
            testing = false
        }
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

// MARK: - 随机码

/// 一次放松操作：输对随机码以后执行 action
struct CodeRequest: Identifiable {
    let id = UUID()
    let what: String
    let action: () -> Void
}

/// 照着打一遍随机码：码画在格子里（不能选中复制），输入框里粘贴会被清掉，3 分钟内有效
struct CodeSheet: View {
    let request: CodeRequest
    let done: () -> Void
    @State private var code = CodeSheet.make()
    @State private var input = ""
    @State private var started = Date()
    @State private var message: String?

    static func make() -> String {
        let alphabet = Array("ACDEFHJKMNPQRTUVWXY34679")  // 去掉了容易看混的字符
        let chars = (0..<20).map { _ in alphabet.randomElement()! }
        return stride(from: 0, to: 20, by: 4).map { String(chars[$0..<$0 + 4]) }.joined(separator: "-")
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(uiImage: UIImage(named: "pose-heart") ?? UIImage()).resizable().scaledToFit().frame(height: 110)
            Text("真的需要吗？").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink)
            Text("要改的：\(request.what)\n照着打一遍下面这串码再决定（不能复制粘贴，3 分钟内有效）。")
                .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            // 一个字一个格子画出来，没法长按选中
            let chars = Array(code)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 12), spacing: 6) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch)).font(.system(size: 19, weight: .heavy, design: .monospaced)).foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ch == "-" ? Color.clear : Theme.soft))
                }
            }
            .allowsHitTesting(false)
            TextField("在这里一个一个字打", text: $input)
                .font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundColor(Theme.ink)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.soft))
                .onChange(of: input) { old, new in
                    // 一次多出来好几个字：是粘贴，退回去
                    if new.count - old.count > 1 { input = old; message = "要一个字一个字打哦" }
                }
            if let message { Text(message).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.junk) }
            HStack(spacing: 12) {
                Button("算了，不改了") { done() }.buttonStyle(Pill(small: true))
                Button("确定") { check() }.buttonStyle(Pill())
            }
        }
        .padding(24)
        .background(SkyBackground())
        .preferredColorScheme(.light)
    }

    private func check() {
        if Date().timeIntervalSince(started) > 180 {
            code = Self.make(); input = ""; started = Date()
            message = "超过 3 分钟了，换了一串新的码"
            return
        }
        let norm = { (s: String) in s.uppercased().filter { $0.isLetter || $0.isNumber } }
        guard !input.isEmpty, norm(input) == norm(code) else { message = "打得不对，再看仔细一点"; return }
        request.action()
        done()
    }
}
