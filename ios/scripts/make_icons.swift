import AppKit
// 用法：swift scripts/make_icons.swift <角色目录> <输出目录>
// 从大肥鱼的图里裁出脑袋，做 App 图标（1024，浅蓝底）和锁屏页图标（512，透明底）
let src = CommandLine.arguments[1], out = CommandLine.arguments[2]
func cg(_ path: String) -> CGImage { NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func save(_ img: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func render(size: Int, background: CGColor?, image: CGImage, crop: CGRect) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
    ctx.interpolationQuality = .high
    let piece = image.cropping(to: crop)!
    let s = CGFloat(size) / crop.width
    ctx.draw(piece, in: CGRect(x: 0, y: 0, width: crop.width * s, height: crop.height * s))
    return ctx.makeImage()!
}
// 比心的那张姿势图是完整的（表情图上有为摆尾巴挖掉的几块），脑袋在上半部分
let heart = cg("\(src)/pose-heart.png")
let head = CGRect(x: 110, y: 0, width: 600, height: 600)
save(render(size: 1024, background: CGColor(red: 0.85, green: 0.91, blue: 0.99, alpha: 1), image: heart, crop: head), "\(out)/AppIcon.png")
save(render(size: 512, background: nil, image: heart, crop: head), "\(out)/shield-whale.png")
