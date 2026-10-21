import AppKit
import AVFoundation
import WebKit
import FocusGuardCore

/// 能接收鼠标的无边框面板
private final class MascotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 桌宠：屏幕上的 Live2D 角色。会换表情、说话、在气泡里提醒，还会飞去浏览器用法术关网页。
@MainActor
final class Mascot: NSObject, WKScriptMessageHandler, AVSpeechSynthesizerDelegate {
    enum Mood: String { case idle, happy, excited, watching, angry, shy }

    struct BubbleButton {
        var id: String
        var title: String
        var primary = false
        var waitSeconds = 0
    }

    /// 窗口大小：下方 188 高是角色，上方留给对话气泡
    static let size = NSSize(width: 280, height: 400)

    /// App 里带的桌宠网页、运行库和内置角色（模型由 scripts/fetch_mascot.sh 下载）
    static var assetsDir: URL? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Mascot"),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("vendor/lib/pixi.min.js").path)
        else { return nil }
        return dir
    }

    /// 实际加载的目录：~/Library/Application Support/FocusGuard/Mascot。
    /// 启动时把 App 里的文件复制过来；characters/ 下用户自己加的角色包保留不动。
    static var webRoot: URL {
        Config.fileURL.deletingLastPathComponent().appendingPathComponent("Mascot")
    }

    static func installWebFiles() {
        guard let src = assetsDir else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: webRoot.appendingPathComponent("characters"), withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] where name != "characters" {
            let target = webRoot.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: src.appendingPathComponent(name), to: target)
        }
        let builtIn = src.appendingPathComponent("characters")
        for name in (try? fm.contentsOfDirectory(atPath: builtIn.path)) ?? [] {
            let target = webRoot.appendingPathComponent("characters/\(name)")
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: builtIn.appendingPathComponent(name), to: target)
        }
    }

    /// 可选的角色：(id, 名字)
    static func characters() -> [(id: String, name: String)] {
        let dir = webRoot.appendingPathComponent("characters")
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        return ids.compactMap { id in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(id)/character.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return (id, json["name"] as? String ?? id)
        }
    }

    /// 要显示的角色
    var characterID = "mao"

    var voiceEnabled = true
    private var panel: NSPanel?
    private var web: WKWebView?
    private var ready = false
    private var pendingJS: [String] = []
    private var hitRects: [CGRect] = []
    private var mouseTimer: Timer?
    private var dragging = false
    private var busy = false
    private var mood: Mood = .idle
    private let synth = AVSpeechSynthesizer()
    private var onButton: ((String) -> Void)?
    private var onReason: ((ReasonKind) -> Void)?
    var onError: (String) -> Void = { _ in }
    /// 用户戳了她一下
    var onTapped: () -> Void = {}

    /// 平时站的位置（可以拖动，记住）
    private var home: NSPoint {
        get {
            if let s = UserDefaults.standard.string(forKey: "mascotHome") { return NSPointFromString(s) }
            let v = NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: v.maxX - Self.size.width - 8, y: v.minY)
        }
        set { UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: "mascotHome") }
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func show() {
        guard panel == nil, Self.assetsDir != nil else { return }
        Self.installWebFiles()
        let dir = Self.webRoot
        let id = Self.characters().contains { $0.id == characterID } ? characterID : "mao"
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "mascot")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let web = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        var page = URLComponents(url: dir.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
        page.queryItems = [URLQueryItem(name: "character", value: id)]
        web.loadFileURL(page.url!, allowingReadAccessTo: dir)
        self.web = web

        let panel = MascotPanel(contentRect: NSRect(origin: home, size: Self.size),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = web
        panel.orderFrontRegardless()
        self.panel = panel
        synth.delegate = self

        // 鼠标在角色或气泡上才接收点击，其余地方点穿到下面的窗口
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }
    }

    func hide() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        synth.stopSpeaking(at: .immediate)
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "mascot")
        panel?.close()
        panel = nil
        web = nil
        ready = false
        pendingJS = []
    }

    private func updateClickThrough() {
        guard let panel else { return }
        if dragging { panel.ignoresMouseEvents = false; return }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - panel.frame.minX, y: panel.frame.maxY - m.y)
        panel.ignoresMouseEvents = !hitRects.contains { $0.contains(p) }
    }

    // MARK: 表情、说话

    func setMood(_ m: Mood) {
        guard m != mood, !busy else { return }
        mood = m
        js("mascot.setMood('\(m.rawValue)')")
    }

    /// 气泡里说一句话；speak 为要读出来的内容（nil 不读）
    func say(_ text: String, speak: String? = nil, buttons: [BubbleButton] = [], reasons: [ReasonKind] = [],
             onButton: ((String) -> Void)? = nil, onReason: ((ReasonKind) -> Void)? = nil) {
        self.onButton = onButton
        self.onReason = onReason
        let b = buttons.map { ["id": $0.id, "title": $0.title, "style": $0.primary ? "primary" : "secondary",
                               "waitSeconds": $0.waitSeconds] as [String: Any] }
        let short: [ReasonKind: String] = [.tired: "😴 累了", .bored: "😐 无聊", .avoiding: "😣 逃避", .relaxing: "😌 放松"]
        let r = reasons.map { ["id": $0.rawValue, "title": short[$0] ?? $0.label] }
        js("mascot.say(\(json(text)), \(json(b)), \(json(r)))")
        if let speak { self.speak(speak) }
    }

    func hideBubble() {
        onButton = nil
        onReason = nil
        js("mascot.hideBubble()")
    }

    /// 说完自动收起的一句话
    func remark(_ text: String, mood: Mood? = nil, seconds: Double = 4) {
        if let mood { js("mascot.setMood('\(mood.rawValue)')") }
        say(text, speak: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.onButton == nil else { return }
                self.hideBubble()
                self.js("mascot.setMood('\(self.mood.rawValue)')")
            }
        }
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.pitchMultiplier = 1.4
        u.rate = 0.52
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.js("mascot.setSpeaking(true)") }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.js("mascot.setSpeaking(false)") }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.js("mascot.setSpeaking(false)") }
    }

    // MARK: 施法关网页

    /// 飞到浏览器窗口右上角，挥魔杖放出星星，关掉网页，再飞回来
    func castAndClose(line: String, browserBundleID: String?, close: @escaping () -> Void) {
        guard let panel, !busy else { close(); return }
        busy = true
        js("mascot.setMood('angry')")
        say(line, speak: line)

        let target = browserBundleID.flatMap(Self.frontWindowFrame(bundleID:))
        let visible = (target.flatMap { t in NSScreen.screens.first { $0.frame.intersects(t) } } ?? NSScreen.main)?.visibleFrame
            ?? panel.frame
        var dest = panel.frame.origin
        if let t = target {
            // 让角色的头尽量靠近浏览器顶部的标签栏（角色在窗口下方 188 高的区域里）
            dest = NSPoint(x: min(t.maxX - Self.size.width * 0.7, visible.maxX - Self.size.width),
                           y: max(visible.minY, min(t.maxY - Self.size.height + 10, visible.maxY - Self.size.height)))
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = target == nil ? 0 : 0.7
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(dest)
        }
        after(0.8) { self.js("mascot.cast(-1, -0.7)") }
        after(1.6) {
            close()
            self.js("mascot.burst()")
        }
        after(3.2) {
            self.hideBubble()
            self.busy = false
            self.js("mascot.setMood('\(self.mood.rawValue)')")
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.8
                panel.animator().setFrameOrigin(self.home)
            }
        }
    }

    /// 某个 App 最前面那个窗口的位置（Cocoa 坐标）；读位置不需要屏幕录制权限
    static func frontWindowFrame(bundleID: String) -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict), r.width > 200, r.height > 200 else { continue }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        return nil
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
    }

    /// 开发用：把当前画面存成 PNG
    func snapshot(to url: URL, done: @escaping () -> Void) {
        guard let web else { done(); return }
        web.takeSnapshot(with: nil) { image, _ in
            if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            done()
        }
    }

    var isReady: Bool { ready }

    // MARK: 和网页通信

    func js(_ code: String) {
        guard ready, let web else { pendingJS.append(code); return }
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    private func json(_ v: Any) -> String {
        if let s = v as? String, let d = try? JSONSerialization.data(withJSONObject: [s]),
           let t = String(data: d, encoding: .utf8) { return String(t.dropFirst().dropLast()) }
        guard let d = try? JSONSerialization.data(withJSONObject: v) else { return "null" }
        return String(data: d, encoding: .utf8) ?? "null"
    }

    nonisolated func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let type = body["type"] as? String ?? ""
        let id = body["id"] as? String
        let dx = body["dx"] as? Double ?? 0
        let dy = body["dy"] as? Double ?? 0
        let rects = (body["rects"] as? [[String: Double]] ?? []).map {
            CGRect(x: $0["x"] ?? 0, y: $0["y"] ?? 0, width: $0["w"] ?? 0, height: $0["h"] ?? 0)
        }
        let error = body["message"] as? String
        Task { @MainActor in
            switch type {
            case "ready":
                self.ready = true
                let queued = self.pendingJS
                self.pendingJS = []
                queued.forEach { self.js($0) }
            case "hitRects":
                self.hitRects = rects
            case "dragBy":
                self.dragging = true
                if let p = self.panel { p.setFrameOrigin(NSPoint(x: p.frame.minX + dx, y: p.frame.minY - dy)) }
            case "dragEnd":
                self.dragging = false
                if let p = self.panel, !self.busy { self.home = p.frame.origin }
            case "button":
                if let id { self.onButton?(id) }
            case "reason":
                if let id, let kind = ReasonKind(rawValue: id) { self.onReason?(kind) }
            case "tapped":
                self.onTapped()
            case "error":
                self.onError(error ?? "桌宠加载失败")
            default:
                break
            }
        }
    }
}
