import AppKit
import SwiftUI
import FocusGuardCore

/// 设置页的数据。改动立刻交给 onChange 保存，不需要“保存”按钮。
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue && !replacing { onChange(config) } }
    }
    /// 最近一次在浏览器里看到的网址，用于“从浏览器添加”
    @Published var browserURL: String?
    /// 浏览器扩展最近一次上报的时间
    @Published var extensionLastSeen: Date?
    @Published var serverError: String?
    /// 大模型判断的最近状态
    @Published var labelerStatus: String?
    /// 当前显示的设置分组
    @Published var tab: SettingsTab = .sites
    /// 让桌宠演示一次施法（不会真的关网页）
    var previewMascot: () -> Void = {}
    private let onChange: (Config) -> Void
    private var replacing = false

    init(config: Config, onChange: @escaping (Config) -> Void) {
        self.config = config
        self.onChange = onChange
    }

    /// 配置文件在外部被修改时同步过来，不触发保存
    func replace(with config: Config) {
        replacing = true
        self.config = config
        replacing = false
    }
}

enum SettingsTab: String, CaseIterable {
    case sites = "网站", apps = "App", force = "强制关闭", reminders = "提醒", content = "内容记录", ai = "AI 判断"
}

@MainActor
enum SettingsWindow {
    /// 开发用：把某个设置分组画成 PNG
    static func renderPNG(model: SettingsModel, tab: SettingsTab, to url: URL) {
        model.tab = tab
        let view = NSHostingView(rootView: SettingsView(model: model, tab: tab).frame(width: 760, height: 680))
        // 列表是系统表格控件，要放进窗口并跑一下布局才画得出来
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var tab: SettingsTab = .sites
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("设置").font(.system(size: 22, weight: .semibold))
                Spacer()
                Picker("", selection: $model.tab) {
                    ForEach(SettingsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Group {
                switch model.tab {
                case .sites:
                    RuleListEditor(
                        note: "在这些网站上连续刷太久，会弹窗劝你休息。",
                        placeholder: "输入网址或域名，如 zhihu.com、youtube.com/shorts",
                        rules: $model.config.junkSites, browserURL: model.browserURL, isSite: true)
                case .apps:
                    RuleListEditor(
                        note: "名字里包含这些文字的 App（或 Bundle ID 完全相同），算作没营养的内容。",
                        placeholder: "输入 App 名称，如 抖音",
                        rules: $model.config.junkApps, browserURL: nil, isSite: false)
                case .force:
                    ForceSettings(config: $model.config, browserURL: model.browserURL)
                case .reminders:
                    ReminderSettings(config: $model.config, previewMascot: model.previewMascot)
                case .content:
                    ContentSettings(model: model)
                case .ai:
                    AISettings(model: model)
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 840, alignment: .leading)

            HStack {
                Text("改动会立即生效").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开配置文件") {
                    NSWorkspace.shared.open([Config.fileURL],
                                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                            configuration: NSWorkspace.OpenConfiguration())
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
        }
        .onAppear { if !embedded { model.tab = tab } }
    }
}

/// 可增删的规则列表。网站列表支持从浏览器当前网页填入。
struct RuleListEditor: View {
    let note: String
    let placeholder: String
    @Binding var rules: [String]
    let browserURL: String?
    let isSite: Bool

    @State private var input = ""
    @State private var selection: Set<String> = []
    @State private var message: String?

    private var browserRule: String? { browserURL.flatMap(Classifier.siteRule(from:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note).font(.callout).foregroundStyle(.secondary)

            if isSite, let rule = browserRule {
                HStack {
                    Image(systemName: "safari")
                    Text("浏览器当前网页：**\(rule)**").lineLimit(1)
                    Spacer()
                    Button(rules.contains(rule) ? "已在列表中" : "添加这个网站") { add(rule) }
                        .disabled(rules.contains(rule))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
            }

            List(selection: $selection) {
                ForEach(rules, id: \.self) { Text($0) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand(perform: removeSelected)

            HStack {
                TextField(placeholder, text: $input).onSubmit { add(input) }
                Button("添加") { add(input) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("删除所选", action: removeSelected)
                    .disabled(selection.isEmpty)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func add(_ raw: String) {
        let rule: String?
        if isSite {
            rule = Classifier.siteRule(from: raw)
        } else {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            rule = name.isEmpty ? nil : name
        }
        guard let rule else {
            message = "“\(raw)”看起来不是网址或域名"
            return
        }
        if rules.contains(rule) {
            message = "\(rule) 已经在列表中了"
        } else {
            rules.append(rule)
            message = nil
        }
        input = ""
    }

    private func removeSelected() {
        rules.removeAll { selection.contains($0) }
        selection = []
    }
}

struct ForceSettings: View {
    @Binding var config: Config
    let browserURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $config.forceCloseEnabled) {
                Text("开启强制关闭").font(.headline)
            }
            .toggleStyle(.switch)
            HStack(spacing: 24) {
                MinutesStepper(title: "连续看", value: $config.forceCloseMinutes, range: 1...240, suffix: "分钟后关闭")
                MinutesStepper(title: "之后", value: $config.forceCloseCooldownMinutes, range: 1...240, suffix: "分钟内禁止打开")
            }
            .disabled(!config.forceCloseEnabled)
            Divider()
            RuleListEditor(
                note: "只对下面这些网站强制关闭（只关当前网页，不关浏览器）。",
                placeholder: "输入网址或域名，如 douyin.com",
                rules: $config.forceCloseSites, browserURL: browserURL, isSite: true)
        }
    }
}

struct ReminderSettings: View {
    @Binding var config: Config
    var previewMascot: () -> Void = {}

    var body: some View {
        Form {
            Section("连续刷多久弹窗提醒") {
                MinutesStepper(title: "白天", value: $config.daytimeLimitMinutes, range: 1...240, suffix: "分钟")
                MinutesStepper(title: "夜间", value: $config.nightLimitMinutes, range: 1...240, suffix: "分钟")
                HStack {
                    Text("夜间时段")
                    Picker("", selection: $config.nightStartHour) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                    Text("到")
                    Picker("", selection: $config.nightEndHour) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                }
            }
            Section("每日额度") {
                MinutesStepper(title: "每天没营养的内容最多", value: $config.dailyBudgetMinutes, range: 0...600, suffix: "分钟（0 = 不限）")
                Toggle("额度用完后直接关掉没营养的网页（否则只提醒）", isOn: $config.budgetCloses)
                    .disabled(config.dailyBudgetMinutes == 0)
            }
            Section("工作时段") {
                Toggle("工作时段更严格", isOn: $config.workHoursEnabled)
                if config.workHoursEnabled {
                    HStack(spacing: 4) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Toggle(["", "日", "一", "二", "三", "四", "五", "六"][day], isOn: Binding(
                                get: { config.workDays.contains(day) },
                                set: { on in
                                    if on { config.workDays.append(day) } else { config.workDays.removeAll { $0 == day } }
                                    config.workDays.sort()
                                }))
                            .toggleStyle(.button)
                        }
                    }
                    HStack {
                        Picker("", selection: $config.workStartHour) {
                            ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                        Text("到")
                        Picker("", selection: $config.workEndHour) {
                            ForEach(1..<25, id: \.self) { Text("\($0):00").tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    MinutesStepper(title: "工作时段连续刷", value: $config.workLimitMinutes, range: 1...60, suffix: "分钟就提醒")
                }
            }
            Section("桌宠") {
                Toggle("显示桌宠：用她代替弹窗提醒，时间到了会飞过去用法术关网页", isOn: $config.mascotEnabled)
                Toggle("说话时读出来", isOn: $config.mascotVoice).disabled(!config.mascotEnabled)
                if Mascot.assetsDir == nil {
                    Text("没有找到桌宠模型。在项目目录运行 scripts/fetch_mascot.sh 下载后重新安装。")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("可以拖动她换位置；戳她一下会告诉你今天刷了多久。角色为 Live2D 官方示例模型 Mao。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("演示一次施法（不会真的关网页）") { previewMascot() }.disabled(!config.mascotEnabled)
                }
            }
            Section("逐级加强") {
                Toggle("第二次提醒起“再刷”要等倒计时，第三次起还要写一句理由", isOn: $config.frictionEnabled)
                Toggle("打开没营养的内容前，先停下来深呼吸几秒（10 分钟内最多一次）", isOn: $config.pauseBeforeJunk)
                Stepper("等待 \(config.frictionWaitSeconds) 秒", value: $config.frictionWaitSeconds, in: 3...60)
            }
            Section("其他") {
                MinutesStepper(title: "点“再刷一会儿”后", value: $config.snoozeMinutes, range: 1...60, suffix: "分钟再提醒")
                MinutesStepper(title: "离开超过", value: $config.sessionBreakMinutes, range: 1...60, suffix: "分钟，连续时长清零")
            }
        }
        .formStyle(.grouped)
    }
}

struct MinutesStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            TextField("", value: $value, format: .number)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
            Stepper("", value: $value, in: range, step: 1).labelsHidden()
            Text(suffix)
        }
    }
}

struct ContentSettings: View {
    @ObservedObject var model: SettingsModel

    private static let scopeNotes: [ContentScope: (String, String)] = [
        .junk: ("只记录没营养网站", "没营养网站和强制关闭网站上看的内容会被记下来，其他网页一律不记。"),
        .all: ("记录所有网页", "所有网页的标题、作者、标签和停留时长都会记下来，分析会更全面。"),
        .off: ("不记录", "只统计时长，不记录看了什么。"),
    ]

    private var extensionFolder: URL? {
        FileManager.default.fileExists(atPath: ExtensionFiles.folder.path) ? ExtensionFiles.folder : nil
    }

    var body: some View {
        Form {
            Section("记录哪些网页的内容") {
                Picker("", selection: $model.config.contentScope) {
                    ForEach([ContentScope.junk, .all, .off], id: \.self) { scope in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.scopeNotes[scope]!.0)
                            Text(Self.scopeNotes[scope]!.1).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(scope)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("记录的是标题、作者、标签、简介和观看时长，不录屏、不读正文。只保存在这台电脑上。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("永不记录的网站") {
                RuleListEditor(
                    note: "银行、支付、邮箱、医疗、政务等网站：连标题都不记，时长统计里只显示为“🔒 隐私网站”。",
                    placeholder: "输入网址或域名",
                    rules: $model.config.sensitiveSites, browserURL: model.browserURL, isSite: true)
                    .frame(height: 220)
            }

            Section("Chrome 扩展") {
                HStack(spacing: 6) {
                    Circle().fill(model.extensionLastSeen == nil ? Color.secondary : Color.green).frame(width: 8, height: 8)
                    if let seen = model.extensionLastSeen {
                        Text("已连接，最后一次收到数据：\(seen.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("还没收到扩展的数据")
                    }
                }
                if let error = model.serverError {
                    Text("⚠️ \(error)").foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("安装方法（只需一次）：").bold()
                    Text("1. 点下面的“打开扩展文件夹”")
                    Text("2. 点“打开 Chrome 扩展页”，打开右上角的“开发者模式”")
                    Text("3. 点“加载已解压的扩展程序”，选中刚才那个文件夹")
                    Text("App 更新后，在 Chrome 扩展页点一下扩展上的刷新按钮即可。").foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack {
                    if let folder = extensionFolder {
                        Button("打开扩展文件夹") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    Button("打开 Chrome 扩展页") {
                        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
                            NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: chrome,
                                                    configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                }
            }

        }
        .formStyle(.grouped)
    }
}

/// 浏览器扩展放在固定位置，App 挪动或重新编译后 Chrome 仍能找到
enum ExtensionFiles {
    static var folder: URL {
        Config.fileURL.deletingLastPathComponent().appendingPathComponent("ChromeExtension")
    }

    /// 启动时把 App 里带的扩展复制过去（覆盖旧版本）
    static func install() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
              FileManager.default.fileExists(atPath: source.path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] {
            let target = folder.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: source.appendingPathComponent(name), to: target)
        }
    }
}

struct AISettings: View {
    @ObservedObject var model: SettingsModel
    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var testResult: String?
    @State private var testing = false

    private var llm: Binding<LLMConfig> { $model.config.llm }
    private var needsKey: Bool { model.config.llm.provider != .ollama }

    private static let providerNames: [LLMProvider: String] = [
        .anthropic: "Anthropic", .deepseek: "DeepSeek", .openai: "OpenAI 兼容接口", .ollama: "本机 Ollama",
    ]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: llm.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("让大模型判断内容有没有营养").font(.headline)
                        Text("学习类视频不再提醒、不会被强制关闭；娱乐内容照常处理。还没判断出来时按网站规则。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                if model.config.contentScope == .off {
                    Text("⚠️ 需要先在“内容记录”里开启记录，并安装 Chrome 扩展").foregroundStyle(.orange)
                }
                Toggle("劝导文案由大模型结合你正在看的内容来写", isOn: llm.smartNudges)
                    .disabled(!model.config.llm.enabled)
                Picker("每天几点自动写小结", selection: $model.config.digestHour) {
                    ForEach(17..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                .disabled(!model.config.llm.enabled)
                if let status = model.labelerStatus {
                    Text(status).font(.callout).foregroundStyle(status.hasPrefix("⚠️") ? .orange : .secondary)
                }
            }

            Section("你的标准") {
                TextEditor(text: llm.preferences)
                    .font(.callout)
                    .frame(height: 70)
                Text("用自己的话写什么算有营养、什么算没营养，会原样告诉大模型。").font(.caption).foregroundStyle(.secondary)
            }

            Section("模型") {
                Picker("服务商", selection: llm.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { Text(Self.providerNames[$0]!).tag($0) }
                }
                .onChange(of: model.config.llm.provider) { provider in
                    applyDefaults(for: provider)
                    loadKey()
                }
                TextField("判断用的模型", text: llm.taggingModel)
                TextField("写报告用的模型（日报功能下一步开放）", text: llm.reportModel)
                TextField("接口地址（留空用默认）", text: llm.baseURL,
                          prompt: Text(defaultBaseURL))
                if needsKey {
                    HStack {
                        SecureField("API Key", text: $apiKey, prompt: Text(keySaved ? "已保存在钥匙串（重新输入可替换）" : "粘贴 API Key"))
                        Button("保存") {
                            APIKeyStore.set(apiKey, for: model.config.llm.provider)
                            apiKey = ""
                            loadKey()
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                HStack {
                    Button(testing ? "测试中…" : "用两条示例测试") { runTest() }
                        .disabled(testing || (needsKey && !keySaved))
                    if let testResult {
                        Text(testResult).font(.callout).textSelection(.enabled)
                    }
                }
            }

            Section("写进 Obsidian") {
                Toggle("每日小结和每周复盘同时存一份到 Obsidian", isOn: $model.config.writeToObsidian)
                if model.config.writeToObsidian {
                    if let root = DigestWriter.obsidianRoot(model.config) {
                        Text(root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("⚠️ 没找到 Obsidian 的库，请手动选择文件夹").font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("选择文件夹…") { chooseFolder() }
                        if !model.config.obsidianFolder.isEmpty {
                            Button("恢复自动") { model.config.obsidianFolder = "" }
                        }
                        if let root = DigestWriter.obsidianRoot(model.config), FileManager.default.fileExists(atPath: root.path) {
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                        }
                    }
                }
            }

            Section("会发送什么") {
                Text("每条内容只发送：网站名、标题、作者、标签、简介、视频时长。不发送完整网址，不发送你什么时候看的。同一条内容只判断一次。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadKey)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { model.config.obsidianFolder = url.path }
    }

    private var defaultBaseURL: String {
        switch model.config.llm.provider {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com"
        case .ollama: return "http://127.0.0.1:11434/v1"
        }
    }

    private func loadKey() {
        keySaved = APIKeyStore.get(model.config.llm.provider) != nil
    }

    /// 换服务商时，模型名还是别家的默认值就换成新服务商的默认值
    private func applyDefaults(for provider: LLMProvider) {
        let defaults: [LLMProvider: (String, String)] = [
            .anthropic: ("claude-haiku-5-5", "claude-opus-5-5"),
            .deepseek: ("deepseek-flash", "deepseek-v4-pro"),
            .openai: ("", ""),
            .ollama: ("qwen3:8b", "qwen3:8b"),
        ]
        let known = Set(defaults.values.flatMap { [$0.0, $0.1] })
        if known.contains(model.config.llm.taggingModel) { model.config.llm.taggingModel = defaults[provider]!.0 }
        if known.contains(model.config.llm.reportModel) { model.config.llm.reportModel = defaults[provider]!.1 }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let llm = model.config.llm
        let samples = Labeler.samples
        Task {
            var lines: [String] = []
            for s in samples {
                do {
                    let l = try await Labeler.classify(s, llm: llm)
                    lines.append("\(l.isJunk ? "🍟 没营养" : "🥦 有营养") \(l.nutrition)/5 · \(l.category) · \(l.reason)")
                } catch {
                    lines.append("❌ \(error)")
                    break
                }
            }
            testResult = lines.joined(separator: "\n")
            testing = false
        }
    }
}
