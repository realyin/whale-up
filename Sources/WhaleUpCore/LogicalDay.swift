import Foundation

/// 一天从几点开始算。晚上刷到凌晨是常事，零点一过就算新的一天会把一晚上拆成两半，
/// 所以默认凌晨 4 点以前都算前一天（Config.dayStartHour 可改）。
///
/// “某一天”统一用那天日历上的零点表示（DayKey、界面上的日期都用它）；
/// 这一天实际覆盖的时间是 [零点 + startHour, 第二天零点 + startHour)。
public enum LogicalDay {
    nonisolated(unsafe) public static var startHour = 4

    /// 某个时刻算哪一天（返回那天的零点）。传进来的已经是某天零点时原样返回，可以放心重复调用。
    public static func of(_ date: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        if date == midnight { return midnight }
        return calendar.startOfDay(for: date.addingTimeInterval(-Double(startHour) * 3600))
    }

    public static var today: Date { of(Date()) }

    /// 这一天实际覆盖的时间段
    public static func range(_ day: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.date(byAdding: .hour, value: startHour, to: of(day, calendar: calendar))!
        return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    public static func isToday(_ day: Date, calendar: Calendar = .current) -> Bool {
        of(day, calendar: calendar) == of(Date(), calendar: calendar)
    }

    /// 前后第 n 天
    public static func adding(_ days: Int, to day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: of(day, calendar: calendar))!
    }
}
