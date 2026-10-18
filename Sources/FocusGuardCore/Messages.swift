import Foundation

public struct NudgeText: Equatable {
    public var emoji: String
    public var title: String
    public var body: String
}

/// 劝导文案。第一次温和，多次提醒后语气逐渐认真。
public enum Messages {
    public static func make(for n: Nudge) -> NudgeText {
        let what = n.reason.isEmpty ? n.appName : n.reason
        let stats = "这次已经连续刷了 \(n.sessionMinutes) 分钟，今天累计 \(n.todayMinutes) 分钟。"

        if n.isNight {
            let tone: [String] = [
                "夜深了，\(what) 明天还在，但今晚的睡眠过去就没了。",
                "还在刷呀？现在睡，明天会感谢现在的自己。",
                "已经第 \(n.count) 次提醒了。放下它，关灯，去睡觉吧。",
            ]
            return NudgeText(emoji: "🌙", title: "该睡觉啦",
                             body: pick(tone, n.count) + "\n" + stats)
        }

        let tone: [String] = [
            "刷 \(what) 有一会儿了。起来喝口水、伸个懒腰，眼睛也休息一下？",
            "短视频停不下来是正常的，它就是这么设计的。现在主动停下，就赢了一次。",
            "第 \(n.count) 次提醒了。去做点让自己更好的事吧：走走、看会儿书、或者小睡 20 分钟。",
        ]
        return NudgeText(emoji: "☕️", title: "休息一下吧",
                         body: pick(tone, n.count) + "\n" + stats)
    }

    private static func pick(_ options: [String], _ count: Int) -> String {
        options[min(max(count, 1), options.count) - 1]
    }
}
