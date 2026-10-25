import AppKit
import SwiftUI
import WhaleUpCore

/// “问问大肥鱼”的对话窗口：配色和她的气泡一样（深蓝描边、奶白底）
@MainActor
final class ChatWindow {
    let agent: Agent
    private var window: NSWindow?

    init(agent: Agent) {
        self.agent = agent
    }

    /// 角色包里的大头像（characters/<角色>/head.png），没有就不显示头像
    static func avatar(character: String) -> NSImage? {
        NSImage(contentsOf: Mascot.webRoot.appendingPathComponent("characters/\(character)/head.png"))
            ?? Mascot.assetsDir.flatMap { NSImage(contentsOf: $0.appendingPathComponent("characters/\(character)/head.png")) }
    }

    func show(character: String) {
        if window == nil {
            let view = ChatView(agent: agent, avatar: Self.avatar(character: character))
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "问问大肥鱼"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 440, height: 620))
            window.minSize = NSSize(width: 360, height: 420)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("WhaleUpChat")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 开发用：把对话窗口画成 PNG
    static func renderPNG(agent: Agent, avatar: NSImage?, to url: URL, size: NSSize = NSSize(width: 440, height: 620)) {
        let view = NSHostingView(rootView: ChatView(agent: agent, avatar: avatar).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private enum Palette {
    static let paper = Color(red: 1, green: 0.992, blue: 0.976)          // #fffdf9
    static let ink = Color(red: 0.122, green: 0.169, blue: 0.369)        // #1f2b5e
    static let accent = Color(red: 0.239, green: 0.435, blue: 0.839)     // #3d6fd6
    static let soft = Color(red: 0.914, green: 0.941, blue: 0.988)       // #e9f0fc
    static let softInk = Color(red: 0.176, green: 0.247, blue: 0.478)    // #2d3f7a
    static let page = Color(red: 0.957, green: 0.969, blue: 0.992)
    static let warn = Color(red: 0.78, green: 0.33, blue: 0.2)
}

struct ChatView: View {
    @ObservedObject var agent: Agent
    let avatar: NSImage?
    @State private var input = ""
    @FocusState private var focused: Bool

    static let suggestions = ["今天都干了什么？", "刚才那个视频为什么没被关？", "最近有没有出什么错？", "这周哪个网站最费时间？"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if agent.lines.isEmpty { welcome }
                        ForEach(agent.lines) { row($0) }
                        if agent.busy { thinking }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .onChange(of: agent.lines) { _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") } }
                .onChange(of: agent.busy) { _ in proxy.scrollTo("bottom") }
            }
            inputBar
        }
        .background(Palette.page)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            face(36)
            VStack(alignment: .leading, spacing: 2) {
                Text("大肥鱼").font(.system(size: 14, weight: .bold)).foregroundColor(Palette.ink)
                Text(agent.doing ?? "问我今天看了什么、为什么关 / 没关，也能帮你改名单")
                    .font(.system(size: 11)).foregroundColor(Palette.softInk.opacity(0.8)).lineLimit(1)
            }
            Spacer()
            Button { agent.reset() } label: {
                Label("新对话", systemImage: "arrow.counterclockwise").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Palette.soft))
            .foregroundColor(Palette.softInk)
            .disabled(agent.lines.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.paper)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            herBubble("主人好呀～有什么想问我的？比如今天都看了什么、哪个视频为什么没被关、我有没有出错。想加网站进名单也可以直接跟我说。")
            FlowChips(items: Self.suggestions) { agent.send($0) }
                .padding(.leading, 38)
        }
    }

    @ViewBuilder
    private func row(_ line: Agent.Line) -> some View {
        switch line.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(line.text)
                    .font(.system(size: 13)).foregroundColor(.white).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
            }
        case .her:
            herBubble(line.text)
        case .step:
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .bold))
                Text(line.text).font(.system(size: 11))
            }
            .foregroundColor(Palette.softInk.opacity(0.75))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Palette.soft))
            .padding(.leading, 38)
        case .error:
            herBubble(line.text, warn: true)
        }
    }

    private var thinking: some View {
        HStack(alignment: .top, spacing: 8) {
            face(30)
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(agent.doing ?? "在想…").font(.system(size: 12)).foregroundColor(Palette.softInk)
                Button("停") { agent.stop() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Palette.accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.ink.opacity(0.25), lineWidth: 1))
        }
    }

    private func herBubble(_ text: String, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            face(30)
            Text(Self.markdown(text))
                .font(.system(size: 13)).foregroundColor(warn ? Palette.warn : Palette.ink)
                .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(warn ? Palette.warn : Palette.ink, lineWidth: 1.5))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundColor(Palette.accent.opacity(0.35)).padding(3))
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func face(_ size: CGFloat) -> some View {
        if let avatar {
            Image(nsImage: avatar).resizable().interpolation(.high).scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .overlay(Circle().stroke(Palette.ink, lineWidth: 1.5))
                .background(Circle().fill(Palette.soft))
        } else {
            Circle().fill(Palette.soft).frame(width: size, height: size).overlay(Text("🐳").font(.system(size: size * 0.55)))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("问她点什么…（回车发送）", text: $input)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.ink.opacity(focused ? 0.6 : 0.25), lineWidth: 1.2))
            Button(action: send) {
                Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? Palette.accent : Palette.accent.opacity(0.35)))
            }
            .buttonStyle(.plain).disabled(!canSend)
        }
        .padding(12)
        .background(Palette.paper)
        .overlay(Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 1), alignment: .top)
    }

    private var canSend: Bool { !agent.busy && !input.trimmingCharacters(in: .whitespaces).isEmpty }

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

/// 一排能换行的小按钮（建议的问题）
private struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.system(size: 12, weight: .medium)).foregroundColor(Palette.softInk)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Palette.soft))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.accent.opacity(0.35), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                    .onTapGesture { tap(item) }
            }
        }
    }
}
