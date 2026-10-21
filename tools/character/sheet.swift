import AppKit
// 用法：sheet <输出> <图1> <图2> ...（2 列网格，每格 480×413，带文件名）
let args = Array(CommandLine.arguments.dropFirst())
let out = args[0], files = Array(args.dropFirst())
let cell = NSSize(width: 480, height: 413), cols = 2, rows = (files.count + 1) / 2
let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(cols), height: cell.height * CGFloat(rows)))
sheet.lockFocus()
NSColor(white: 0.85, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
for (i, f) in files.enumerated() {
    guard let img = NSImage(contentsOfFile: f) else { continue }
    let col = CGFloat(i % cols), row = CGFloat(rows - 1 - i / cols)
    let dst = NSRect(x: col * cell.width, y: row * cell.height, width: cell.width, height: cell.height)
    let s = min(cell.width / img.size.width, cell.height / img.size.height)
    let r = NSRect(x: dst.midX - img.size.width * s / 2, y: dst.midY - img.size.height * s / 2, width: img.size.width * s, height: img.size.height * s)
    img.draw(in: r)
    ((f as NSString).lastPathComponent as NSString).draw(at: NSPoint(x: dst.minX + 6, y: dst.minY + 6),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.red])
}
sheet.unlockFocus()
try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
