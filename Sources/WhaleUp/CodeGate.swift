import AppKit
import WhaleUpCore

/// 放松管控前的“随机码”：弹出一串每次都不一样的码，画成图片（没法复制），照着手打一遍才放行。
/// 输入框里粘贴会被清掉。通过以后 3 分钟内再放松不用重输（不然调一下步进器就要输一次）
@MainActor
enum CodeGate {
    private static var unlockedUntil = Date.distantPast

    static var isUnlocked: Bool { Date() < unlockedUntil }

    /// 要放松的地方（what）列给用户看；输对了返回 true
    static func confirm(_ what: [String]) -> Bool {
        if isUnlocked { return true }
        let code = RandomCode.make()
        let alert = NSAlert()
        alert.messageText = "要放松管控，先照着打一遍这串码"
        alert.informativeText = "要改的：\(what.joined(separator: "；"))\n\n大肥鱼想让你冷静一下：真的需要吗？打完这串码再决定。（不能复制粘贴，3 分钟内有效）"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "算了，不改了")

        let width: CGFloat = 380
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 110))
        let picture = NSImageView(frame: NSRect(x: 0, y: 46, width: width, height: 56))
        picture.image = image(of: code, width: width, height: 56)
        let field = CodeField(frame: NSRect(x: 0, y: 8, width: width, height: 28))
        field.placeholderString = "在这里一个一个字打"
        field.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        box.addSubview(picture)
        box.addSubview(field)
        alert.accessoryView = box
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let started = Date()
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            if Date().timeIntervalSince(started) > RandomCode.lifetime {
                let late = NSAlert()
                late.messageText = "超过 3 分钟了，这串码作废了"
                late.informativeText = "改动没有生效。真要改，再来一次。"
                late.runModal()
                return false
            }
            if RandomCode.matches(field.stringValue, code) {
                unlockedUntil = Date().addingTimeInterval(RandomCode.lifetime)
                return true
            }
            alert.informativeText = "打得不对，再看仔细一点。\n\n要改的：\(what.joined(separator: "；"))"
        }
    }

    /// 把码画成图片：字之间加点间距、轻微错位，让它不好被识别成文字复制
    static func image(of code: String, width: CGFloat, height: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor(red: 0.91, green: 0.94, blue: 0.99, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            let font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
            let chars = Array(code)
            let step = (rect.width - 24) / CGFloat(chars.count)
            for (i, ch) in chars.enumerated() {
                let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                            .foregroundColor: NSColor(red: 0.12, green: 0.17, blue: 0.37, alpha: 1)]
                let y = (rect.height - 26) / 2 + CGFloat((i * 7) % 5) - 2
                NSAttributedString(string: String(ch), attributes: attrs).draw(at: NSPoint(x: 12 + CGFloat(i) * step, y: y))
            }
            return true
        }
    }
}

/// 只能一个字一个字打的输入框：一次多出来好几个字（粘贴）就退回去
private final class CodeField: NSTextField, NSTextFieldDelegate {
    private var last = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func controlTextDidChange(_ obj: Notification) {
        if stringValue.count - last.count > 1 {
            stringValue = last
            NSSound.beep()
        }
        last = stringValue
    }
}
