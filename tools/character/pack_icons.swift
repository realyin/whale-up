import AppKit
// 用法：pack_icons <图标表.png> <列数> <行数> <输出目录> <名字1> <名字2> …
// 把 Codex 画的一整张图标表（白底、按格子均匀排布）切成一个个透明底的 128×128 小图标，按名字保存成 <名字>.png。
// 白底只从边缘往里抠，图标里面的白色部分保留；每个格子里不连着主体的小碎点（< 150 像素）丢掉。
let args = CommandLine.arguments
guard args.count >= 6, let cols = Int(args[2]), let rows = Int(args[3]) else {
    print("用法：pack_icons <图标表.png> <列数> <行数> <输出目录> <名字…>"); exit(1)
}
let names = Array(args[5...])
let out = args[4]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

guard let img = NSImage(contentsOfFile: args[1]), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("读不了 \(args[1])"); exit(1)
}
let W = cg.width, H = cg.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

// 1. 从边缘把白底抠掉
func isBG(_ i: Int) -> Bool {
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    return (r * 3 + g * 6 + b) / 10 > 225 && max(r, g, b) - min(r, g, b) < 24
}
let N = W * H
let bg = (0..<N).map { isBG($0 * 4) }
// 线稿的小缺口会让白底漏进米饭、云朵这些白色的里面：先把非白的部分加粗 6 像素堵上缺口，
// 从边缘找“真正的外面”，再从外面往白底里最多走 7 步，把加粗吃掉的那圈白边收回来
let R = 6
var thick = bg.map { !$0 }
var tmp = thick
for y in 0..<H { for x in 0..<W where !thick[y * W + x] {
    for dx in -R...R where x + dx >= 0 && x + dx < W && thick[y * W + x + dx] { tmp[y * W + x] = true; break }
} }
thick = tmp
for y in 0..<H { for x in 0..<W where !tmp[y * W + x] {
    for dy in -R...R where y + dy >= 0 && y + dy < H && tmp[(y + dy) * W + x] { thick[y * W + x] = true; break }
} }
var outside = [Bool](repeating: false, count: N)
var stack: [Int] = []
for x in 0..<W { stack += [x, (H - 1) * W + x] }
for y in 0..<H { stack += [y * W, y * W + W - 1] }
// 格子之间的白缝也当边缘
for c in 1..<cols { let x = W * c / cols; for y in 0..<H { stack.append(y * W + x) } }
for r in 1..<rows { let y = H * r / rows; for x in 0..<W { stack.append(y * W + x) } }
func neighbors(_ p: Int) -> [Int] {
    let x = p % W, y = p / W
    return [x > 0 ? p - 1 : -1, x < W - 1 ? p + 1 : -1, y > 0 ? p - W : -1, y < H - 1 ? p + W : -1].filter { $0 >= 0 }
}
while let p = stack.popLast() {
    guard !outside[p], !thick[p] else { continue }
    outside[p] = true
    stack += neighbors(p)
}
var frontier = (0..<N).filter { outside[$0] }
for _ in 0...R {
    var next: [Int] = []
    for p in frontier { for n in neighbors(p) where !outside[n] && bg[n] { outside[n] = true; next.append(n) } }
    frontier = next
}
// 预乘透明度：颜色也要清零，否则透明像素画出来还是白的
for p in 0..<N where outside[p] { for c in 0..<4 { px[p * 4 + c] = 0 } }
// 贴着透明区的浅色描边按亮度变半透明，去掉白毛边
for p in 0..<(W * H) where px[p * 4 + 3] > 0 {
    let x = p % W, y = p / W
    guard x > 0, y > 0, x < W - 1, y < H - 1,
          [p - 1, p + 1, p - W, p + W].contains(where: { px[$0 * 4 + 3] == 0 }) else { continue }
    let i = p * 4
    let lum = (Int(px[i]) * 3 + Int(px[i + 1]) * 6 + Int(px[i + 2])) / 10
    if lum > 180 {
        let a = max(0, min(255, (255 - lum) * 3))
        for c in 0..<3 { px[i + c] = UInt8(Int(px[i + c]) * a / 255) }
        px[i + 3] = UInt8(a)
    }
}

// 2. 连通块，丢掉碎点
var label = [Int32](repeating: 0, count: W * H)
var comps: [(cx: Int, cy: Int, minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int)] = []
for s in 0..<(W * H) where px[s * 4 + 3] > 30 && label[s] == 0 {
    let id = Int32(comps.count + 1)
    var q = [s]; label[s] = id
    var minX = W, minY = H, maxX = 0, maxY = 0, n = 0, sx = 0, sy = 0
    while let p = q.popLast() {
        let x = p % W, y = p / W
        n += 1; sx += x; sy += y
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        for nb in [x > 0 ? p - 1 : -1, x < W - 1 ? p + 1 : -1, y > 0 ? p - W : -1, y < H - 1 ? p + W : -1]
        where nb >= 0 && label[nb] == 0 && px[nb * 4 + 3] > 30 {
            label[nb] = id; q.append(nb)
        }
    }
    comps.append((sx / n, sy / n, minX, minY, maxX, maxY, n))
}

// 3. 按格子合并（星星、水花等不连着主体的小部件也算这个图标），裁成正方形存下来
for (k, name) in names.enumerated() where k < cols * rows {
    let col = k % cols, row = k / cols
    let mine = comps.filter { $0.count >= 150 && $0.cx * cols / W == col && $0.cy * rows / H == row }
    guard !mine.isEmpty else { print("⚠️ 第 \(k + 1) 格（\(name)）是空的"); continue }
    let minX = mine.map(\.minX).min()!, maxX = mine.map(\.maxX).max()!
    let minY = mine.map(\.minY).min()!, maxY = mine.map(\.maxY).max()!
    let side = Int(Double(max(maxX - minX, maxY - minY)) * 1.08)
    let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
    let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)

    // 只拷这个格子里属于它的像素，避免邻格的东西混进来
    var cell = [UInt8](repeating: 0, count: W * H * 4)
    for y in max(0, minY - 2)...min(H - 1, maxY + 2) {
        for x in max(0, minX - 2)...min(W - 1, maxX + 2) where x * cols / W == col && y * rows / H == row {
            let i = (y * W + x) * 4
            for c in 0..<4 { cell[i + c] = px[i + c] }
        }
    }
    let cctx = CGContext(data: &cell, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    guard let cropped = cctx.makeImage()?.cropping(to: rect) else { continue }
    let S = 128
    let octx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    octx.interpolationQuality = .high
    octx.draw(cropped, in: CGRect(x: 0, y: 0, width: S, height: S))
    let path = "\(out)/\(name).png"
    try! NSBitmapImageRep(cgImage: octx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("已生成 \(name).png")
}
