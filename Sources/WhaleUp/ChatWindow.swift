import AppKit
import SwiftUI
import WhaleUpCore

/// “问问大肥鱼”的对话窗口：深海蓝的头部、她的立绘、白卡片气泡、浮在底部的输入框
@MainActor
final class ChatWindow: NSObject, NSWindowDelegate {
    let agent: Agent
    private var window: NSWindow?

    init(agent: Agent) {
        self.agent = agent
    }

    /// 角色包里的图（head.png 大头像、pose-heart.png 立绘），没有就不显示
    static func art(_ name: String, character: String) -> NSImage? {
        NSImage(contentsOf: Mascot.webRoot.appendingPathComponent("characters/\(character)/\(name)"))
            ?? Mascot.assetsDir.flatMap { NSImage(contentsOf: $0.appendingPathComponent("characters/\(character)/\(name)")) }
    }

    static func makeView(agent: Agent, character: String) -> ChatView {
        ChatView(agent: agent, avatar: art("head.png", character: character), pose: art("pose-heart.png", character: character))
    }

    func show(character: String) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: Self.makeView(agent: agent, character: character)))
            window.title = "问问大肥鱼"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 460, height: 680))
            window.minSize = NSSize(width: 380, height: 480)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("WhaleUpChat")
            window.delegate = self
            window.center()
            self.window = window
        }
        // 鲸醒平时只在菜单栏（不算“正在用的程序”），语音输入法这类靠“当前程序 + 焦点输入框”找输入位置的工具会找不到；
        // 对话窗口开着时当成普通程序，关掉再退回菜单栏
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 开发用：把对话窗口画成 PNG
    static func renderPNG(_ view: ChatView, to url: URL, size: NSSize = NSSize(width: 460, height: 680)) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - 配色

private enum Sea {
    static let ink = Color(red: 0.122, green: 0.169, blue: 0.369)         // #1f2b5e 她的描边色
    static let deep = Color(red: 0.086, green: 0.137, blue: 0.341)        // 头部深处
    static let accent = Color(red: 0.239, green: 0.435, blue: 0.839)      // #3d6fd6
    static let light = Color(red: 0.373, green: 0.561, blue: 0.937)
    static let page = Color(red: 0.953, green: 0.965, blue: 0.992)
    static let foam = Color(red: 0.902, green: 0.933, blue: 0.988)
    static let text = Color(red: 0.149, green: 0.180, blue: 0.290)
    static let sub = Color(red: 0.420, green: 0.467, blue: 0.600)
    static let warn = Color(red: 0.83, green: 0.38, blue: 0.24)
}

private extension Font {
    static func cute(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// 四个角各自的圆角（气泡朝说话人那边的角小一点，像小尾巴）
private struct Bubble: Shape {
    var tl: CGFloat = 18, tr: CGFloat = 18, br: CGFloat = 18, bl: CGFloat = 18

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - 界面

struct ChatView: View {
    @ObservedObject var agent: Agent
    let avatar: NSImage?
    let pose: NSImage?
    @State private var input = ""
    @State private var inputHeight: CGFloat = 20

    static let suggestions: [(icon: String, text: String)] = [
        ("sun.max.fill", "今天都干了什么？"),
        ("questionmark.bubble.fill", "刚才那个视频为什么没被关？"),
        ("ladybug.fill", "最近有没有出什么错？"),
        ("sparkles", "推荐一部番给我吧"),
    ]

    /// 连着的几步工具调用并成一行显示
    private enum Item: Identifiable {
        case line(Agent.Line)
        case steps(id: UUID, [String])
        var id: UUID { switch self { case .line(let l): return l.id; case .steps(let id, _): return id } }
    }

    private var items: [Item] {
        var out: [Item] = []
        for line in agent.lines {
            if line.role == .step {
                if case .steps(let id, let names)? = out.last {
                    out[out.count - 1] = .steps(id: id, names.contains(line.text) ? names : names + [line.text])
                } else {
                    out.append(.steps(id: line.id, [line.text]))
                }
            } else {
                out.append(.line(line))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if agent.lines.isEmpty { welcome } else {
                                ForEach(items) { item in
                                    switch item {
                                    case .line(let line): row(line)
                                    case .steps(_, let names): steps(names)
                                    }
                                }
                            }
                            if agent.busy { typing }
                            Color.clear.frame(height: 86).id("bottom")
                        }
                        .padding(.horizontal, 16).padding(.top, 16)
                    }
                    .onChange(of: agent.lines) { _ in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: agent.busy) { _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                inputBar
            }
            .background(Sea.page)
        }
        .background(Sea.page)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: 头部

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Sea.deep, Sea.ink, Sea.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
            // 几颗上浮的泡泡
            Canvas { ctx, size in
                let dots: [(CGFloat, CGFloat, CGFloat)] = [(0.62, 0.30, 7), (0.70, 0.62, 4), (0.78, 0.22, 3), (0.86, 0.50, 9), (0.93, 0.18, 5), (0.55, 0.75, 3)]
                for (x, y, r) in dots {
                    let rect = CGRect(x: size.width * x - r, y: size.height * y - r, width: r * 2, height: r * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.28)), lineWidth: 1.2)
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.55, dy: r * 0.55).offsetBy(dx: -r * 0.25, dy: -r * 0.25)),
                             with: .color(.white.opacity(0.35)))
                }
            }
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    face(46).overlay(Circle().stroke(.white, lineWidth: 2.5))
                    Circle().fill(agent.busy ? Color.orange : Color.green).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Sea.ink, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("大肥鱼").font(.cute(17, .bold)).foregroundColor(.white)
                        Text("鲸鱼女仆").font(.cute(10, .semibold)).foregroundColor(Sea.ink)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(0.85)))
                    }
                    Text(agent.busy ? (agent.doing ?? "在想…") : "在线 · 在屏幕角落数贝壳")
                        .font(.cute(11.5)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer()
                Button { agent.reset() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain).help("新对话").disabled(agent.lines.isEmpty).opacity(agent.lines.isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .frame(height: 104)
        .clipShape(Bubble(tl: 0, tr: 0, br: 22, bl: 22))
        .shadow(color: Sea.ink.opacity(0.25), radius: 10, y: 4)
        .zIndex(1)
    }

    // MARK: 空白页

    private var welcome: some View {
        VStack(spacing: 14) {
            if let pose {
                Image(nsImage: pose).resizable().interpolation(.high).scaledToFit().frame(height: 168)
                    .padding(.top, 4)
            }
            VStack(spacing: 6) {
                Text("主人来啦！").font(.cute(18, .bold)).foregroundColor(Sea.ink)
                Text("今天看了什么、哪个视频为什么没关、我有没有出错，\n想聊番剧聊吃的也行——快说快说！")
                    .font(.cute(12.5)).foregroundColor(Sea.sub).multilineTextAlignment(.center).lineSpacing(3)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.suggestions, id: \.text) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: s.icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Sea.accent)
                            .frame(width: 26, height: 26).background(Circle().fill(Sea.foam))
                        Text(s.text).font(.cute(12.5, .medium)).foregroundColor(Sea.text)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .shadow(color: Sea.ink.opacity(0.07), radius: 6, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { agent.send(s.text) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 消息

    @ViewBuilder
    private func row(_ line: Agent.Line) -> some View {
        switch line.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(line.text).font(.cute(13.5)).foregroundColor(.white).textSelection(.enabled)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Bubble(br: 6).fill(LinearGradient(colors: [Sea.light, Sea.accent], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: Sea.accent.opacity(0.25), radius: 6, y: 3)
            }
        case .her, .error:
            herBubble(line.text, warn: line.role == .error)
        case .step:
            EmptyView()
        }
    }

    private func herBubble(_ text: String, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            face(30)
            Text(Self.markdown(text)).font(.cute(13.5)).foregroundColor(warn ? Sea.warn : Sea.text)
                .lineSpacing(3.5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Bubble(tl: 6).fill(warn ? Color(red: 1, green: 0.95, blue: 0.93) : .white))
                .overlay(Bubble(tl: 6).stroke(warn ? Sea.warn.opacity(0.35) : Sea.ink.opacity(0.06), lineWidth: 1))
                .shadow(color: Sea.ink.opacity(0.08), radius: 8, y: 3)
            Spacer(minLength: 28)
        }
    }

    private func steps(_ names: [String]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 9.5, weight: .bold))
            Text("翻了翻：" + names.joined(separator: " · ")).font(.cute(11))
        }
        .foregroundColor(Sea.sub)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Sea.foam))
        .padding(.leading, 38)
    }

    private var typing: some View {
        HStack(alignment: .center, spacing: 8) {
            face(30)
            HStack(spacing: 8) {
                TypingDots()
                Text(agent.doing ?? "在想…").font(.cute(12)).foregroundColor(Sea.sub)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Bubble(tl: 6).fill(.white))
            .shadow(color: Sea.ink.opacity(0.08), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    private func face(_ size: CGFloat) -> some View {
        if let avatar {
            Image(nsImage: avatar).resizable().interpolation(.high).scaledToFill()
                .frame(width: size, height: size).background(Sea.foam).clipShape(Circle())
        } else {
            Circle().fill(Sea.foam).frame(width: size, height: size).overlay(Text("🐳").font(.system(size: size * 0.55)))
        }
    }

    // MARK: 输入框

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("跟大肥鱼说点什么…").font(.cute(13.5)).foregroundColor(Sea.sub.opacity(0.7)).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                ChatInput(text: $input, height: $inputHeight, onSend: send)
                    .frame(height: min(max(inputHeight, 20), 110))
            }
            .padding(.vertical, 9).padding(.leading, 6)
            Button(action: agent.busy ? agent.stop : send) {
                Image(systemName: agent.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canSend || agent.busy
                                              ? AnyShapeStyle(LinearGradient(colors: [Sea.light, Sea.accent], startPoint: .top, endPoint: .bottom))
                                              : AnyShapeStyle(Sea.sub.opacity(0.25))))
            }
            .buttonStyle(.plain).disabled(!canSend && !agent.busy).help(agent.busy ? "别查了" : "发送（回车）")
            .padding(.bottom, 3)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: Sea.ink.opacity(0.16), radius: 14, y: 4))
        .padding(.horizontal, 14).padding(.bottom, 14)
    }

    private var canSend: Bool { !agent.busy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard canSend else { return }
        agent.send(input)
        input = ""
    }

    /// 她的回答里常有 **粗体**、列表：按 Markdown 显示，保留换行
    static func markdown(_ text: String) -> AttributedString {
        // 只认行内格式（粗体等），列表的“- ”换成圆点
        let text = text.replacingOccurrences(of: #"(?m)^(\s*)[-*] "#, with: "$1• ", options: .regularExpression)
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// 三个一跳一跳的小点
private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Sea.accent.opacity(0.75)).frame(width: 6, height: 6)
                        .offset(y: -3 * max(0, sin((t * 2 * .pi / 1.1) - Double(i) * 0.9)))
                }
            }
        }
        .frame(height: 12)
    }
}

/// 原生的多行输入框（NSTextView）：输入法、语音输入、听写都认它；回车发送，Shift + 回车换行
private struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13.5).rounded
        tv.textColor = NSColor(red: 0.149, green: 0.180, blue: 0.290, alpha: 1)
        tv.insertionPointColor = NSColor(red: 0.239, green: 0.435, blue: 0.839, alpha: 1)
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.setAccessibilityLabel("跟大肥鱼说的话")
        // 窗口出来就把光标放进来
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text && !tv.hasMarkedText() {
            tv.string = text
            context.coordinator.measure(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(_ parent: ChatInput) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            measure(tv)
        }

        func measure(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = ceil(lm.usedRect(for: tc).height)
            DispatchQueue.main.async { self.parent.height = max(20, h) }
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            // 输入法还在拼字时回车交给输入法
            guard selector == #selector(NSResponder.insertNewline(_:)), !tv.hasMarkedText() else { return false }
            if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.option) {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            parent.onSend()
            return true
        }
    }
}

private extension NSFont {
    var rounded: NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
