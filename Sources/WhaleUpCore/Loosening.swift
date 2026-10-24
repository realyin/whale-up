import Foundation

/// 哪些改动算“放松管控”：这些改动要先输随机码才生效。收紧的改动（少看、调小时长、加网站）不设门槛
extension Config {
    /// 和旧配置比，放松了哪些地方；空数组表示没有放松
    public func loosenings(from old: Config) -> [String] {
        var out: [String] = []
        if old.forceCloseEnabled && !forceCloseEnabled { out.append("关掉强制关闭") }
        if forceCloseEnabled && forceCloseMinutes > old.forceCloseMinutes {
            out.append("强制关闭从 \(Int(old.forceCloseMinutes)) 分钟调到 \(Int(forceCloseMinutes)) 分钟")
        }
        let removed = Set(old.forceCloseSites).subtracting(forceCloseSites)
        if !removed.isEmpty { out.append("从强制关闭名单删掉 \(removed.sorted().joined(separator: "、"))") }
        if old.dailyBudgetMinutes > 0 && (dailyBudgetMinutes == 0 || dailyBudgetMinutes > old.dailyBudgetMinutes) {
            out.append(dailyBudgetMinutes == 0 ? "取消每日额度" : "每日额度从 \(Int(old.dailyBudgetMinutes)) 分钟调到 \(Int(dailyBudgetMinutes)) 分钟")
        }
        if old.budgetCloses && !budgetCloses && dailyBudgetMinutes > 0 { out.append("关掉“额度用完直接关”") }
        return out
    }
}

/// 一次性随机码：放松管控前要照着手打一遍。去掉了容易看混的字符（0/O、1/I/L、2/Z、5/S、8/B、6/G）
public enum RandomCode {
    static let alphabet = Array("ACDEFHJKMNPQRTUVWXY34679")
    public static let length = 20
    /// 有效期（秒）
    public static let lifetime: Double = 180

    /// 如 "K7QX-MP3R-..."，四个一组方便看
    public static func make<G: RandomNumberGenerator>(using rng: inout G) -> String {
        let chars = (0..<length).map { _ in alphabet.randomElement(using: &rng)! }
        return stride(from: 0, to: length, by: 4).map { String(chars[$0..<min($0 + 4, length)]) }.joined(separator: "-")
    }

    public static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return make(using: &rng)
    }

    /// 输入对不对：不管大小写、空格和横线
    public static func matches(_ input: String, _ code: String) -> Bool {
        let norm = { (s: String) in s.uppercased().filter { $0.isLetter || $0.isNumber } }
        return !input.isEmpty && norm(input) == norm(code)
    }
}
