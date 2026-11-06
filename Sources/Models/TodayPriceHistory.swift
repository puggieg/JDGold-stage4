import Foundation

public enum MarketDay {
    public static let timeZoneIdentifier = "Asia/Shanghai"
    private static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: timeZoneIdentifier)!; return value
    }()
    public static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func minute(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60) }
}
public struct MinutePriceSample: Codable, Equatable, Sendable {
    public let minute: Date
    public var observedAt: Date
    public var price: Double
    public var high: Double
    public var low: Double
    public init(minute: Date, observedAt: Date, price: Double, high: Double? = nil, low: Double? = nil) {
        self.minute = minute; self.observedAt = observedAt; self.price = price; self.high = high ?? price; self.low = low ?? price
    }
    public var isValid: Bool {
        [price,high,low,minute.timeIntervalSince1970,observedAt.timeIntervalSince1970].allSatisfy { $0.isFinite } &&
        low > 0 && low <= price && price <= high && MarketDay.minute(observedAt) == minute
    }
}
public struct TodayPriceHistory: Equatable, Sendable {
    public var day: String
    public var values: [Instrument: [MinutePriceSample]]
    public init(day: String, values: [Instrument: [MinutePriceSample]] = [:]) { self.day = day; self.values = values }
    public func samples(for instrument: Instrument, now: Date) -> [MinutePriceSample] {
        guard day == MarketDay.key(now) else { return [] }
        return (values[instrument] ?? []).filter { $0.isValid && MarketDay.key($0.observedAt) == day && $0.observedAt <= now }
            .sorted { $0.minute < $1.minute }
    }
    public static func recording(_ prices: GoldPrices, in history: TodayPriceHistory, now: Date) -> TodayPriceHistory {
        let day = MarketDay.key(now)
        var changed = history.day == day ? history : TodayPriceHistory(day: day)
        let minute = MarketDay.minute(now)
        for instrument in Instrument.allCases {
            let info = prices.priceInfo(for: instrument)
            // 只记录新一轮成功抓取的有效行情，失败缓存不能伪装成新的价格点。
            guard QuoteFreshness.usable(info, now: now) else { continue }
            var samples = changed.samples(for: instrument, now: now)
            if let index = samples.firstIndex(where: { $0.minute == minute }) {
                samples[index].price = info.doublePrice; samples[index].observedAt = now
                samples[index].high = max(samples[index].high, info.doublePrice)
                samples[index].low = min(samples[index].low, info.doublePrice)
            } else { samples.append(MinutePriceSample(minute: minute, observedAt: now, price: info.doublePrice)) }
            // 北京时间一天最多 1440 个分钟桶，不因高频刷新膨胀。
            changed.values[instrument] = Array(samples.suffix(1440))
        }
        return changed
    }
}
public struct SparklinePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let startsSegment: Bool
}
public enum SparklineGeometry {
    // 坐标归一化到 0...1，AppKit 只负责投影和画线，便于验证平盘/缺口/极端值。
    public static func points(_ samples: [MinutePriceSample]) -> [SparklinePoint] {
        let sorted = samples.filter { $0.isValid }.sorted { $0.minute < $1.minute }
        guard let first = sorted.first, let last = sorted.last,
              let minimum = sorted.map({ $0.price }).min(), let maximum = sorted.map({ $0.price }).max() else { return [] }
        let span = last.minute.timeIntervalSince(first.minute)
        let amplitude = maximum - minimum
        guard span.isFinite, amplitude.isFinite else { return [] }
        return sorted.enumerated().map { index, sample in
            let x = span > 0 ? sample.minute.timeIntervalSince(first.minute) / span : 0.5
            let y = amplitude > 0 ? (sample.price - minimum) / amplitude : 0.5
            let gap = index == 0 || sample.minute.timeIntervalSince(sorted[max(0, index - 1)].minute) > 120
            return SparklinePoint(x: x, y: y, startsSegment: gap)
        }
    }
    public static func extremes(_ samples: [MinutePriceSample]) -> (high: Double, low: Double)? {
        let valid = samples.filter { $0.isValid }
        guard let high = valid.map({ $0.high }).max(), let low = valid.map({ $0.low }).min() else { return nil }
        return (high, low)
    }
}
