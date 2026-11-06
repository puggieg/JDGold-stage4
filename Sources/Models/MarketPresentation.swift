import Foundation

public enum SourceTimestamp {
    public static func milliseconds(_ raw: String?) -> Date? {
        guard let raw = raw, let number = Double(raw), number.isFinite, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number / 1000)
    }
    public static func sina(date: String, time: String) -> Date? {
        let d = date.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 3, (1...12).contains(d[1]), (1...31).contains(d[2]),
              (0...23).contains(t[0]), (0...59).contains(t[1]), (0...59).contains(t[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: t[2])
        guard let result = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)
        return back == parts ? result : nil
    }
}

public enum MarketPresentation {
    // “休市/延迟”是数据状态提示；没有交易日历时不猜测具体休市原因。
    public static func isDelayed(_ info: PriceInfo, now: Date) -> Bool {
        if !info.isValid || info.isStale { return true }
        if let date = info.sourceUpdatedAt, now.timeIntervalSince(date) >= 300 { return true }
        if let date = info.lastPriceChangeAt, now.timeIntervalSince(date) >= 300 { return true }
        return false
    }
    public static func movement(_ info: PriceInfo) -> String {
        guard let change = info.numericChangeRate else { return "—" }
        return change == 0 ? "— 0.00%" : "\(change > 0 ? "▲" : "▼")\(String(format: "%.2f", abs(change)))%"
    }
    public static func distance(target: Double, info: PriceInfo) -> String {
        guard info.isValid else { return "距现价 —" }
        return String(format: "距现价 %+.2f%%", (target / info.doublePrice - 1) * 100)
    }
    public static func lowestBanks(_ prices: GoldPrices, now: Date) -> Set<Instrument> {
        let banks = Instrument.allCases.filter { $0.group == .domestic }
        // 缺失任意一家有效报价时不声称已比较三家；并列最低全部标记。
        guard banks.allSatisfy({ !isDelayed(prices.priceInfo(for: $0), now: now) }),
              let lowest = banks.map({ prices.priceInfo(for: $0).doublePrice }).min() else { return [] }
        return Set(banks.filter { prices.priceInfo(for: $0).doublePrice == lowest })
    }
    public static func policyText(_ policy: RepeatPolicy) -> String {
        switch policy {
        case .once: return "仅一次"
        case .everyCrossing: return "每次穿越"
        case .continuous(let seconds): return "持续提醒 · \(String(format: "%g", seconds / 60)) 分钟"
        }
    }
}
