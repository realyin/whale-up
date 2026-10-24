import DeviceActivity
import FamilyControls
import SwiftUI
import UserNotifications

@main
struct WhaleUpApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

/// 主页：大肥鱼在上面，下面是要管的 App、每天的时长、今天再多看、今天的统计
struct HomeView: View {
    @State private var settings = LimitSettings.load()
    @State private var authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    @State private var picking = false
    @State private var error: String?
    @State private var shielded = Limiter.isShielded
    @State private var breathe = false
    @Environment(\.scenePhase) private var phase

    private var line: String {
        if !authorized { return "让我来帮你管住手吧～\n先允许我用“屏幕使用时间”。" }
        if settings.isEmpty { return "选一下要管哪些 App 吧，抖音、B 站都行。" }
        if shielded { return "今天刷够了哦，明天凌晨 \(settings.dayStartHour) 点见～" }
        return "每天 \(settings.dailyMinutes + settings.todayExtra) 分钟，用完我就施法！"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                mascot
                if !authorized {
                    Button(action: authorize) {
                        Label("允许使用屏幕使用时间", systemImage: "hourglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(Pill())
                } else {
                    card("要管的 App 和网站") {
                        Button { picking = true } label: {
                            HStack {
                                Text(selectionSummary).foregroundColor(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                        }
                    }
                    card("每天一共能刷") {
                        Stepper(value: $settings.dailyMinutes, in: 5...240, step: 5) {
                            Text("\(settings.dailyMinutes) 分钟").font(.system(.title3, design: .rounded).bold())
                        }
                        Text("看满就锁上，当天不管什么时候再打开都会被关掉。一天从凌晨 \(settings.dayStartHour) 点开始算。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    card("今天再多看") {
                        HStack(spacing: 10) {
                            ForEach([5, 10, 30], id: \.self) { m in
                                Button("\(m) 分钟") { grant(m) }.buttonStyle(Pill(small: true))
                            }
                        }
                        Text(settings.todayExtra > 0 ? "今天已经多加了 \(settings.todayExtra) 分钟，用完还会锁上。" : "真想多看才点。加的时间只管今天，用完还会锁上。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    card(nil) {
                        DeviceActivityReport(.today, filter: filter).frame(minHeight: 260)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundColor(.red) }
            }
            .padding(20)
        }
        .background(Theme.soft.ignoresSafeArea())
        .familyActivityPicker(isPresented: $picking, selection: $settings.selection)
        .onChange(of: settings) { _ in apply() }
        .onChange(of: phase) { p in
            if p == .active {
                settings = LimitSettings.load()
                shielded = Limiter.isShielded
                authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            }
        }
    }

    // MARK: 大肥鱼和她的气泡

    private var mascot: some View {
        VStack(spacing: 6) {
            Text(line)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.ink, lineWidth: 2.5))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).padding(5))
            // 没设置好时比心求你设置，平时喝着奶茶陪你，用完了就抱着抱枕睡觉
            Image(shielded ? "pose-sleep_curl" : authorized && !settings.isEmpty ? "pose-milktea" : "pose-heart")
                .resizable().scaledToFit().frame(height: 200)
                .scaleEffect(x: breathe ? 1.006 : 1, y: breathe ? 1.02 : 1, anchor: .bottom)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathe)
                .onAppear { breathe = true }
        }
        .padding(.top, 8)
    }

    private func card<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.system(.headline, design: .rounded)).foregroundColor(Theme.ink) }
            content()
        }
        .padding(title == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.ink, lineWidth: 2))
    }

    private var selectionSummary: String {
        let s = settings.selection
        if settings.isEmpty { return "还没选，点这里选" }
        var parts: [String] = []
        if !s.applicationTokens.isEmpty { parts.append("\(s.applicationTokens.count) 个 App") }
        if !s.categoryTokens.isEmpty { parts.append("\(s.categoryTokens.count) 个类别") }
        if !s.webDomainTokens.isEmpty { parts.append("\(s.webDomainTokens.count) 个网站") }
        return "已选 " + parts.joined(separator: " · ")
    }

    /// 统计范围：今天（从凌晨 dayStartHour 点起）；选了 App 就只看这些
    private var filter: DeviceActivityFilter {
        let now = Date()
        var start = Calendar.current.date(bySettingHour: settings.dayStartHour, minute: 0, second: 0, of: now)!
        if start > now { start = Calendar.current.date(byAdding: .day, value: -1, to: start)! }
        let interval = DateInterval(start: start, end: now)
        let s = settings.selection
        if settings.isEmpty {
            return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone]))
        }
        return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone]),
                                    applications: s.applicationTokens, categories: s.categoryTokens, webDomains: s.webDomainTokens)
    }

    // MARK: 动作

    private func authorize() {
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                authorized = AuthorizationCenter.shared.authorizationStatus == .approved
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                self.error = "没有拿到屏幕使用时间的权限：\(error.localizedDescription)"
            }
        }
    }

    private func apply() {
        settings.save()
        do {
            try Limiter.restart(settings)
            error = nil
        } catch {
            self.error = "开始计时失败：\(error.localizedDescription)"
        }
    }

    private func grant(_ minutes: Int) {
        do {
            try Limiter.grant(minutes)
            settings = LimitSettings.load()
            shielded = false
            error = nil
        } catch {
            self.error = "加时间失败：\(error.localizedDescription)"
        }
    }
}

/// 女仆装风格的按钮：深蓝描边、下面一道阴影
struct Pill: ButtonStyle {
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(small ? .subheadline : .headline, design: .rounded).weight(.bold))
            .foregroundColor(small ? Theme.ink : .white)
            .padding(.horizontal, small ? 14 : 20).padding(.vertical, small ? 8 : 14)
            .background(Capsule().fill(small ? Theme.soft : Theme.accent))
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
            .shadow(color: Theme.ink, radius: 0, y: configuration.isPressed ? 0 : 3)
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}
