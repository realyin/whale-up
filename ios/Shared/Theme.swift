import DeviceActivity
import SwiftUI

/// 和 Mac 版气泡同一套女仆装配色
enum Theme {
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.37)
    static let paper = Color(red: 1, green: 0.99, blue: 0.976)
    static let accent = Color(red: 0.24, green: 0.44, blue: 0.84)
    static let soft = Color(red: 0.91, green: 0.94, blue: 0.99)
    static let junk = Color(red: 0.92, green: 0.41, blue: 0.20)
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
