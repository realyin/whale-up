import AppKit
// 用法：pack <素材目录> <输出角色目录>
// 素材目录里：reference.webp（原图，带字）以及 Codex 生成的 blink/angry/watching/shy/cast.png（各自可选）
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let W = 960, H = 826

struct Bitmap { var px: [UInt8] }
func load(_ path: String) -> Bitmap? {
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    var px = [UInt8](repeating: 0, count: W * H * 4)
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))  // 统一缩放到 960×826
    return Bitmap(px: px)
}
func i4(_ x: Int, _ y: Int) -> Int { (y * W + x) * 4 }
func clearPx(_ b: inout Bitmap, _ i: Int) { b.px[i] = 0; b.px[i+1] = 0; b.px[i+2] = 0; b.px[i+3] = 0 }
func clearRect(_ b: inout Bitmap, _ r: (Int, Int, Int, Int)) {
    for y in max(0, r.1)..<min(H, r.3) { for x in max(0, r.0)..<min(W, r.2) { clearPx(&b, i4(x, y)) } }
}
func cutout(_ b: inout Bitmap, rects: [(Int, Int, Int, Int)]) {
    func bg(_ i: Int) -> Bool {
        let r = Int(b.px[i]), g = Int(b.px[i+1]), bl = Int(b.px[i+2])
        return (r * 3 + g * 6 + bl) / 10 > 200 && max(r, g, bl) - min(r, g, bl) < 28
    }
    var seen = [Bool](repeating: false, count: W * H)
    var st: [(Int, Int)] = []
    for x in 0..<W { st.append((x, 0)); st.append((x, H - 1)) }
    for y in 0..<H { st.append((0, y)); st.append((W - 1, y)) }
    while let (x, y) = st.popLast() {
        guard x >= 0, y >= 0, x < W, y < H, !seen[y * W + x] else { continue }
        seen[y * W + x] = true
        let i = i4(x, y)
        guard bg(i) else { continue }
        clearPx(&b, i)
        st += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    }
    for r in rects { clearRect(&b, r) }
    for _ in 0..<2 {  // 去白边
        var fade: [(Int, UInt8)] = []
        for y in 1..<(H - 1) { for x in 1..<(W - 1) {
            let i = i4(x, y)
            guard b.px[i+3] == 255, [i4(x+1, y), i4(x-1, y), i4(x, y+1), i4(x, y-1)].contains(where: { b.px[$0 + 3] == 0 }) else { continue }
            let lum = (Int(b.px[i]) * 3 + Int(b.px[i+1]) * 6 + Int(b.px[i+2])) / 10
            if lum > 170 { fade.append((i, UInt8(max(0, min(255, (255 - lum) * 3))))) }
        } }
        for (i, a) in fade {
            let k = Double(a) / 255
            b.px[i] = UInt8(Double(b.px[i]) * k); b.px[i+1] = UInt8(Double(b.px[i+1]) * k); b.px[i+2] = UInt8(Double(b.px[i+2]) * k); b.px[i+3] = a
        }
    }
    // 去掉小于 300 像素的孤立小块
    var label = [Int](repeating: 0, count: W * H); var comp = 0
    for s in 0..<(W * H) where b.px[s * 4 + 3] > 20 && label[s] == 0 {
        comp += 1; var members: [Int] = []; var q = [s]; label[s] = comp
        while let p = q.popLast() {
            members.append(p)
            let x = p % W, y = p / W
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < W && ny < H {
                let n = ny * W + nx
                if label[n] == 0 && b.px[n * 4 + 3] > 20 { label[n] = comp; q.append(n) }
            }
        }
        if members.count < 300 { for m in members { clearPx(&b, m * 4) } }
    }
}
func save(_ b: Bitmap, crop: CGRect, to path: String) {
    var px = b.px
    let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let img = ctx.makeImage()!.cropping(to: crop)!
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// 原图上画的字和装饰（左上原点）
let textRects: [(Int, Int, Int, Int)] = [
    (518, 0, 960, 240), (535, 240, 960, 315), (465, 30, 530, 120), (35, 235, 100, 295), (55, 315, 90, 350),
    (625, 390, 740, 432), (640, 450, 725, 505), (835, 570, 890, 640), (10, 595, 100, 712), (228, 708, 312, 742), (283, 692, 332, 745),
]
let crop = CGRect(x: 40, y: 40, width: 915, height: 750)    // 所有帧共用的裁剪范围（上方留出伸懒腰举手的空间）
let tailRect = (735, 355, 955, 640)                           // 尾巴（原图坐标）

guard var idle = load("\(src)/reference.webp") else { fatalError("没有 reference.webp") }
cutout(&idle, rects: textRects)
// 切出尾巴
var tail = Bitmap(px: [UInt8](repeating: 0, count: W * H * 4))
for y in tailRect.1..<tailRect.3 { for x in tailRect.0..<tailRect.2 {
    let i = i4(x, y); for k in 0..<4 { tail.px[i + k] = idle.px[i + k] }
} }
try? FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
let tailCrop = CGRect(x: tailRect.0, y: tailRect.1, width: tailRect.2 - tailRect.0, height: tailRect.3 - tailRect.1)
save(tail, crop: tailCrop, to: "\(dst)/tail.png")

var images: [String: String] = [:]
var frames: [(String, Bitmap)] = [("idle", idle)]
for name in ["blink", "angry", "watching", "shy", "cast", "yawn", "sleep", "stretch", "eat1", "eat2"] {
    guard var b = load("\(src)/\(name).png") else { continue }
    cutout(&b, rects: [])
    frames.append((name, b))
}
// 对齐：每一帧和原图的轮廓比较，找重合最好的平移量，再把这一帧挪过去
func mask(_ b: Bitmap, scale: Int) -> [Bool] {
    let w = W / scale, h = H / scale
    var m = [Bool](repeating: false, count: w * h)
    // 只用不会随动作变化的部位（底部的裙摆、腿和鞋，原图 y 620–790）来对齐
    for y in 0..<h { for x in 0..<w {
        let oy = y * scale
        m[y * w + x] = oy >= 620 && oy < 790 && b.px[i4(x * scale, oy) + 3] > 128
    } }
    return m
}
func bestShift(_ a: [Bool], _ b: [Bool], w: Int, h: Int, range: ClosedRange<Int>, around: (Int, Int) = (0, 0)) -> (Int, Int) {
    var best = (0, 0), bestCost = Int.max
    for dy in range { for dx in range {
        let sx = around.0 + dx, sy = around.1 + dy
        var cost = 0
        for y in 0..<h { for x in 0..<w {
            let fx = x - sx, fy = y - sy
            let bv = fx >= 0 && fy >= 0 && fx < w && fy < h ? b[fy * w + fx] : false
            if a[y * w + x] != bv { cost += 1 }
        } }
        if cost < bestCost { bestCost = cost; best = (sx, sy) }
    } }
    return best
}
func shifted(_ b: Bitmap, dx: Int, dy: Int) -> Bitmap {
    var out = Bitmap(px: [UInt8](repeating: 0, count: W * H * 4))
    for y in 0..<H { for x in 0..<W {
        let fx = x - dx, fy = y - dy
        guard fx >= 0, fy >= 0, fx < W, fy < H else { continue }
        let s = i4(fx, fy), d = i4(x, y)
        for k in 0..<4 { out.px[d + k] = b.px[s + k] }
    } }
    return out
}
let idleCoarse = mask(idle, scale: 4)
let idleFine = mask(idle, scale: 2)
frames = frames.map { (name, b) in
    guard name != "idle" else { return (name, b) }
    let c = bestShift(idleCoarse, mask(b, scale: 4), w: W / 4, h: H / 4, range: -12...12)
    let f = bestShift(idleFine, mask(b, scale: 2), w: W / 2, h: H / 2, range: -2...2, around: (c.0 * 2, c.1 * 2))
    print("\(name) 对齐平移：(\(f.0 * 2), \(f.1 * 2))")
    return (name, shifted(b, dx: f.0 * 2, dy: f.1 * 2))
}

for (name, var b) in frames {
    clearRect(&b, tailRect)   // 尾巴统一由单独的部件来画
    save(b, crop: crop, to: "\(dst)/\(name).png")
    if ["idle", "angry", "watching", "shy", "cast"].contains(name) { images[name] = "\(name).png" }
    print("已生成 \(name).png")
}
// 尾巴在画布上的位置：裁剪后坐标；旋转中心在尾巴根部（左下）
let at = [tailRect.0 - Int(crop.minX), tailRect.1 - Int(crop.minY)]
var spec: [String: Any] = [
    "name": "鲸鱼娘", "kind": "sprite", "height": 125, "images": images,
    "parts": [["image": "tail.png", "at": at, "pivot": [6, 230], "swing": 6, "period": 2.6]],
    "headAt": [0.22, 0.08], "castFrom": [0.5, 0.62], "castFromCast": [0.05, 0.37],
    // 气泡配色取自她的女仆装：深蓝描边、奶白底、蝴蝶结的蓝
    "nickname": "大肥鱼",
    "theme": ["paper": "#fffdf9", "ink": "#1f2b5e", "accent": "#3d6fd6", "accent-ink": "#ffffff",
              "soft": "#e9f0fc", "soft-ink": "#2d3f7a", "stitch": "rgba(61, 111, 214, .4)", "lace": "#ffffff"],
]
if frames.contains(where: { $0.0 == "blink" }) { spec["blink"] = "blink.png" }
// ---- 新姿势：每组单独抠图，按组内各帧的公共外框裁剪（同组帧相对位置不变，播放时按脚底中心对齐）----
func bbox(_ b: Bitmap) -> CGRect? {
    var minX = W, minY = H, maxX = -1, maxY = -1
    for y in 0..<H { for x in 0..<W where b.px[i4(x, y) + 3] > 20 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}
/// 返回保存的文件名；素材不全就返回 nil
func packPose(_ files: [String]) -> [String]? {
    var bitmaps: [(String, Bitmap)] = []
    for f in files {
        guard var b = load("\(src)/\(f).png") else { return nil }
        cutout(&b, rects: [])
        bitmaps.append((f, b))
    }
    var union: CGRect?
    for (_, b) in bitmaps { if let r = bbox(b) { union = union.map { $0.union(r) } ?? r } }
    guard let union else { return nil }
    let crop = union.insetBy(dx: -4, dy: -4).intersection(CGRect(x: 0, y: 0, width: W, height: H))
    return bitmaps.map { (f, b) in
        save(b, crop: crop, to: "\(dst)/pose-\(f).png")
        print("已生成 pose-\(f).png")
        return "pose-\(f).png"
    }
}

// 小动作：同一个动作可以有几种姿势，每次随机挑一种
let have = Set(frames.map(\.0))
var actions: [String: Any] = [:]
func add(_ name: String, _ variant: [String: Any]) {
    var list = (actions[name] as? [String: Any])?["variants"] as? [[String: Any]] ?? []
    list.append(variant)
    actions[name] = ["variants": list]
}
if have.contains("yawn") { add("yawn", ["frames": ["yawn.png"], "seconds": 2.8]) }
if have.contains("sleep") { add("sleep", ["frames": ["sleep.png"], "loop": true, "effect": "zzz"]) }
if have.contains("stretch") { add("stretch", ["frames": ["stretch.png"], "seconds": 3.5]) }
if have.contains("eat1") && have.contains("eat2") {
    add("eat", ["frames": ["eat1.png", "eat2.png"], "fps": 1.2, "seconds": 8, "effect": "rice"])
}
let poses: [(String, [String], [String: Any])] = [
    ("eat", ["eat_sit1", "eat_sit2"], ["fps": 1.2, "seconds": 8, "effect": "rice"]),
    ("sleep", ["sleep_curl"], ["loop": true, "effect": "zzz"]),
    ("stretch", ["stretch_stand"], ["seconds": 3.5]),
    ("swim", ["swim1", "swim2"], ["fps": 1.6, "seconds": 7, "effect": "bubbles"]),
    ("dance", ["dance1", "dance2"], ["fps": 2.2, "seconds": 7, "effect": "notes"]),
    ("work", ["work"], ["seconds": 10]),
    ("heart", ["heart"], ["seconds": 3.5, "effect": "hearts"]),
    ("milktea", ["milktea"], ["seconds": 6]),
    ("read", ["read"], ["seconds": 10]),
]
for (name, files, options) in poses {
    guard let saved = packPose(files) else { continue }
    var v = options
    v["frames"] = saved
    v["ownPose"] = true
    add(name, v)
}
spec["actions"] = actions
let json = try! JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(dst)/character.json"))
print("尾巴部件位置 \(at)")
