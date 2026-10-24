import AppKit
import SwiftUI
import WhaleUpCore

/// 劝导弹窗。浮在所有窗口之上，包括全屏播放的视频。
@MainActor
final class NudgeWindow {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ text: NudgeText, isNight: Bool, snoozeMinutes: Int, friction: Friction = .none,
              onRest: @escaping () -> Void, onSnooze: @escaping (_ note: String?) -> Void,
              onReason: @escaping (ReasonKind) -> Void = { _ in }) {
        close()
        let view = NudgeView(
            text: text, isNight: isNight, snoozeMinutes: snoozeMinutes, friction: friction,
            onRest: { [weak self] in self?.close(); onRest() },
            onSnooze: { [weak self] note in self?.close(); onSnooze(note) },
            onReason: onReason)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.orderFrontRegardless()
        if case .writeReason = friction { panel.makeKey() }  // 要打字，需要成为键盘焦点
        NSSound(named: "Glass")?.play()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }

    /// 开发用：把弹窗画成 PNG，便于调整样式（不需要屏幕录制权限）
    static func renderPNG(_ text: NudgeText, isNight: Bool, friction: Friction = .none, to url: URL) {
        let view = NSHostingView(rootView: NudgeView(text: text, isNight: isNight, snoozeMinutes: 5, friction: friction,
                                                     onRest: {}, onSnooze: { _ in }, onReason: { _ in }))
        view.frame.size = view.fittingSize
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private struct NudgeView: View {
    let text: NudgeText
    let isNight: Bool
    let snoozeMinutes: Int
    var friction: Friction = .none
    let onRest: () -> Void
    let onSnooze: (String?) -> Void
    let onReason: (ReasonKind) -> Void
    @State private var reason: ReasonKind?
    @State private var waited = 0
    @State private var note = ""
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var waitSeconds: Int {
        switch friction {
        case .none: return 0
        case .wait(let s): return s
        case .writeReason(let s): return s
        }
    }
    private var needsNote: Bool { if case .writeReason = friction { return true } else { return false } }
    private var canSnooze: Bool { waited >= waitSeconds && (!needsNote || Friction.isAcceptableReason(note)) }

    var body: some View {
        VStack(spacing: 14) {
            Text(text.emoji).font(.system(size: 52))
            Text(text.title).font(.title.bold())
            Text(text.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                Text(reason == nil ? "为什么在刷？点一下就好" : "记下了，谢谢 🙏")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(ReasonKind.allCases, id: \.self) { kind in
                        Button(kind.label) {
                            if reason == nil { onReason(kind) }
                            reason = kind
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(reason == kind ? .accentColor : nil)
                        .disabled(reason != nil && reason != kind)
                    }
                }
            }
            .padding(.top, 2)
            VStack(spacing: 8) {
                Button(action: onRest) {
                    Text(isNight ? "好，关掉它去睡觉" : "好，关掉它休息一下").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                if needsNote {
                    TextField("真的还要继续？写一句理由", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 4)
                }
                Button(snoozeTitle) { onSnooze(needsNote ? note.trimmingCharacters(in: .whitespacesAndNewlines) : nil) }
                    .buttonStyle(.link)
                    .disabled(!canSnooze)
                    .padding(.top, 2)
            }
            .padding(.top, 6)
        }
        .onReceive(ticker) { _ in if waited < waitSeconds { waited += 1 } }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 420)
    }

    private var snoozeTitle: String {
        let left = waitSeconds - waited
        return left > 0 ? "再刷 \(snoozeMinutes) 分钟（\(left) 秒后可点）" : "再刷 \(snoozeMinutes) 分钟"
    }
}

/// “打开前先停一下”：切到没营养的内容时，先深呼吸几秒再决定
@MainActor
final class PausePanel {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(site: String, detail: String, seconds: Int, onLeave: @escaping () -> Void) {
        panel?.close()
        let view = PauseView(site: site, detail: detail, seconds: seconds,
                             onLeave: { [weak self] in self?.close(); onLeave() },
                             onContinue: { [weak self] in self?.close() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

private struct PauseView: View {
    let site: String
    let detail: String
    let seconds: Int
    let onLeave: () -> Void
    let onContinue: () -> Void
    @State private var left = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Text("🫁").font(.system(size: 44))
            Text("要打开 \(site) 吗？").font(.title2.bold())
            Text(left > 0 ? "先深呼吸，\(left) 秒后再决定" : "想好了吗？").foregroundStyle(.secondary)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                Button(action: onLeave) { Text("不看了").frame(minWidth: 90) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                Button(action: onContinue) { Text("继续看").frame(minWidth: 90) }
                    .controlSize(.large)
                    .disabled(left > 0)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 360)
        .onAppear { left = seconds }
        .onReceive(ticker) { _ in if left > 0 { left -= 1 } }
    }
}

/// 右上角的小提示，几秒后自动消失，不打断操作
@MainActor
final class Toast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, seconds: Double = 5) {
        panel?.close()
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.preferredMaxLayoutWidth = 320

        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])

        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = box
        panel.setContentSize(box.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - box.fittingSize.width - 16, y: screen.maxY - 16))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.close()
                self?.panel = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
