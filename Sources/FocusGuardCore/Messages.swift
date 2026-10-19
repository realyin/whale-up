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

        if n.overBudget {
            let tone = [
                "今天给自己定的额度已经用完了。说好的事，就从现在开始做到。",
                "额度用完还在刷，等于在透支明天的自己。关掉它吧。",
                "第 \(n.count) 次提醒了，今天的额度早就用完了。",
            ]
            return NudgeText(emoji: "⛽️", title: "今日额度用完了", body: pick(tone, n.count) + "\n" + stats)
        }

        if n.isWorkTime {
            let tone = [
                "现在是工作时间，\(what) 先放一放，回到手头的事上吧。",
                "工作时间刷 \(what)，下班时会后悔的。先把要紧的事做完。",
                "第 \(n.count) 次提醒了。工作时间，关掉它。",
            ]
            return NudgeText(emoji: "💼", title: "工作时间", body: pick(tone, n.count) + "\n" + stats)
        }

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
