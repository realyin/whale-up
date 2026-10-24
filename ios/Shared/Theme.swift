import DeviceActivity
import SwiftUI

/// 和 Mac 版气泡同一套女仆装配色
/// 颜色全部写死、不跟系统深色模式变：用系统的“次要文字”颜色时，深色模式下会变成浅灰，在奶白底上看不清
enum Theme {
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.37)        // 主要文字、描边
    static let muted = Color(red: 0.33, green: 0.38, blue: 0.53)      // 次要文字（在白底上对比度够）
    static let paper = Color(red: 1, green: 0.99, blue: 0.976)        // 气泡
    static let card = Color.white
    static let accent = Color(red: 0.24, green: 0.44, blue: 0.84)
    static let soft = Color(red: 0.91, green: 0.94, blue: 0.99)
    static let track = Color(red: 0.89, green: 0.92, blue: 0.97)      // 进度条底色
    static let junk = Color(red: 0.92, green: 0.41, blue: 0.20)
    static let skyTop = Color(red: 0.78, green: 0.88, blue: 0.99)
}

/// 页面背景：上面浅蓝天空，往下渐渐变白
struct SkyBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.skyTop, Theme.soft, Color(red: 0.98, green: 0.985, blue: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// 白色卡片：圆角、柔和的阴影，不再用粗描边
struct CardBox<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.accent) }
                    Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(Theme.ink)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 阴影只给底下的白色卡片，不然里面的字也会带一圈光晕
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
            .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 6))
    }
}

/// 她的对话气泡：和 Mac 版一样，奶白底、深蓝描边、内圈虚线、左上角名牌
struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.paper)
                .shadow(color: Theme.ink.opacity(0.12), radius: 0, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4])).padding(5))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.ink, lineWidth: 2.5))
            .overlay(alignment: .topLeading) {
                Text("大肥鱼")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.paper)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.ink))
                    .offset(x: 16, y: -10)
            }
    }
}

/// 圆形进度：中间写用了几分钟 / 一共几分钟
struct UsageRing: View {
    let used: Double
    let total: Double

    var body: some View {
        let p = min(1, used / max(1, total))
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 14)
            Circle().trim(from: 0, to: p)
                .stroke(p >= 1 ? Theme.junk : p > 0.8 ? Color(red: 0.96, green: 0.6, blue: 0.2) : Theme.accent,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(used / 60))")
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink)
                Text("/ \(Int(total / 60)) 分钟")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
            }
        }
        .frame(width: 118, height: 118)
    }
}

extension DeviceActivityReport.Context {
    /// 今天各个 App 用了多久
    static let today = Self("today")
}

func formatMinutes(_ seconds: TimeInterval) -> String {
    let m = Int((seconds / 60).rounded())
    if m < 1 { return seconds > 0 ? "不到 1 分钟" : "0 分钟" }
    if m < 60 { return "\(m) 分钟" }
    return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
}
