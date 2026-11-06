import Foundation

public struct ExchangeRate: Equatable, Sendable {
    // 1 美元对应多少人民币；不要把 USD/CNY 误当成人民币兑美元。
    public let yuanPerDollar: Double
    public let sourceUpdatedAt: Date
    public let lastSuccessAt: Date
    public var isStale: Bool
    public init(yuanPerDollar: Double, sourceUpdatedAt: Date, lastSuccessAt: Date, isStale: Bool = false) {
        self.yuanPerDollar = yuanPerDollar; self.sourceUpdatedAt = sourceUpdatedAt
        self.lastSuccessAt = lastSuccessAt; self.isStale = isStale
    }
}
public enum QuoteFreshness {
    public static let maximumAge: TimeInterval = 300
    public static func recent(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        // 超过五分钟或来源时间明显在未来，都不用于新的决策指标。
        return age.isFinite && age >= -60 && age < maximumAge
    }
    public static func usable(_ info: PriceInfo, now: Date) -> Bool {
        guard info.isValid, !info.isStale, let fetched = info.lastSuccessAt, recent(fetched, now: now) else { return false }
        if let source = info.sourceUpdatedAt { return recent(source, now: now) }
        return true
    }
    public static func usable(_ rate: ExchangeRate, now: Date) -> Bool {
        !rate.isStale && rate.yuanPerDollar.isFinite && rate.yuanPerDollar > 0 &&
        recent(rate.sourceUpdatedAt, now: now) && recent(rate.lastSuccessAt, now: now)
    }
}
public struct DomesticPremium: Equatable, Sendable {
    public let yuanPerGram: Double
    public let percent: Double
    public let internationalYuanPerGram: Double
    public let yuanPerDollar: Double
    public let rateSourceAt: Date
    public var displayText: String {
        // 消除四舍五入产生的 -0.00 / -0.0，不改动计算结果本身。
        let amount = abs(yuanPerGram) < 0.005 ? 0 : yuanPerGram
        let ratio = abs(percent) < 0.05 ? 0 : percent
        return String(format: "溢价 %+.2f 元/克（%+.1f%%）", amount, ratio)
    }
    public static let explanation = "国内积存金价与伦敦金按美元兑人民币汇率折算价的差额，正值表示国内更贵，百分比以折算价为基准；未计交易费用。"
}
public enum PremiumCalculator {
    public static let gramsPerTroyOunce = 31.1035
    public static func calculate(domestic: PriceInfo, london: PriceInfo, rate: ExchangeRate?, now: Date) -> DomesticPremium? {
        guard let rate = rate, QuoteFreshness.usable(rate, now: now), QuoteFreshness.usable(domestic, now: now),
              QuoteFreshness.usable(london, now: now) else { return nil }
        let base = london.doublePrice * rate.yuanPerDollar / gramsPerTroyOunce
        guard base.isFinite, base > 0 else { return nil }
        let difference = domestic.doublePrice - base
        let ratio = difference / base * 100
        guard difference.isFinite, ratio.isFinite else { return nil }
        return DomesticPremium(yuanPerGram: difference, percent: ratio, internationalYuanPerGram: base,
                               yuanPerDollar: rate.yuanPerDollar, rateSourceAt: rate.sourceUpdatedAt)
    }
}
