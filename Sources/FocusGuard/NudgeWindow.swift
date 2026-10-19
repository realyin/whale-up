import AppKit
import SwiftUI
import FocusGuardCore

/// 劝导弹窗。浮在所有窗口之上，包括全屏播放的视频。
@MainActor
final class NudgeWindow {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ text: NudgeText, isNight: Bool, snoozeMinutes: Int,
              onRest: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        close()
        let view = NudgeView(
            text: text, isNight: isNight, snoozeMinutes: snoozeMinutes,
            onRest: { [weak self] in self?.close(); onRest() },
            onSnooze: { [weak self] in self?.close(); onSnooze() })

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
        NSSound(named: "Glass")?.play()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }

    /// 开发用：把弹窗画成 PNG，便于调整样式（不需要屏幕录制权限）
    static func renderPNG(_ text: NudgeText, isNight: Bool, to url: URL) {
        let view = NSHostingView(rootView: NudgeView(text: text, isNight: isNight, snoozeMinutes: 5,
                                                     onRest: {}, onSnooze: {}))
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
    let onRest: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(text.emoji).font(.system(size: 52))
            Text(text.title).font(.title.bold())
            Text(text.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Button(action: onRest) {
                    Text(isNight ? "好，关掉它去睡觉" : "好，关掉它休息一下").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                Button("再刷 \(snoozeMinutes) 分钟", action: onSnooze)
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 420)
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
