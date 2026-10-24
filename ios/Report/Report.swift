import DeviceActivity
import SwiftUI

/// 今天的统计：系统把数据交给这个扩展画，主 App 拿不到具体数字（苹果的隐私设计）
@main
struct ReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayReport { TodayView(summary: $0) }
    }
}

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let seconds: TimeInterval
}

struct Summary {
    var total: TimeInterval = 0
    var apps: [AppUsage] = []
}

struct TodayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .today
    let content: (Summary) -> TodayView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Summary {
        var byApp: [String: (name: String, seconds: TimeInterval)] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? "未知 App"
                        let id = app.application.bundleIdentifier ?? name
                        byApp[id, default: (name, 0)].seconds += app.totalActivityDuration
                    }
                }
            }
        }
        let apps = byApp.map { AppUsage(id: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .filter { $0.seconds >= 30 }
            .sorted { $0.seconds > $1.seconds }
        return Summary(total: apps.reduce(0) { $0 + $1.seconds }, apps: Array(apps.prefix(8)))
    }
}

struct TodayView: View {
    let summary: Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天").font(.system(.title3, design: .rounded).bold())
                Spacer()
                Text(formatMinutes(summary.total)).font(.system(.title3, design: .rounded).bold()).foregroundColor(Theme.junk)
            }
            if summary.apps.isEmpty {
                Text("今天还没刷，真棒～").foregroundColor(.secondary)
            }
            let longest = summary.apps.first?.seconds ?? 1
            ForEach(summary.apps) { app in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(app.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(formatMinutes(app.seconds)).font(.subheadline).foregroundColor(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Theme.junk.opacity(0.85))
                            .frame(width: max(6, geo.size.width * app.seconds / longest), height: 8)
                    }
                    .frame(height: 8)
                }
            }
        }
        .foregroundColor(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
