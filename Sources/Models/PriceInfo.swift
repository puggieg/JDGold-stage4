import Foundation

// Foundation 值模型不依赖 AppKit；颜色等展示逻辑放在 UI 中。
public struct PriceInfo: Codable, Equatable, Sendable {
    public var price = "--"
    public var yesterdayPrice = "--"
    public var changeRate = ""
    public var changeAmount = ""
    public var isStale = false
    public var lastSuccessAt: Date?
    // 来源时间与最后价格变化时间各有用途，不能用抓取时间冒充来源时间。
    public var sourceUpdatedAt: Date?
    public var lastPriceChangeAt: Date?
    public init(price: String = "--", yesterdayPrice: String = "--", changeRate: String = "", changeAmount: String = "") {
        self.price = price; self.yesterdayPrice = yesterdayPrice
        self.changeRate = changeRate; self.changeAmount = changeAmount
    }
    public var doublePrice: Double { Double(price) ?? 0 }
    public var isValid: Bool { doublePrice.isFinite && doublePrice > 0 }
    public var numericChangeRate: Double? {
        guard let rate = Double(changeRate.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")), rate.isFinite else { return nil }
        return rate
    }
    public var isUp: Bool { (numericChangeRate ?? 0) > 0 }
    public var trendSymbol: String {
        guard let rate = numericChangeRate, rate != 0 else { return "—" }
        return rate > 0 ? "▲" : "▼"
    }
}
public struct GoldPrices: Equatable, Sendable {
    public var values: [Instrument: PriceInfo]
    public init(values: [Instrument: PriceInfo] = [:]) { self.values = values }
    public func priceInfo(for instrument: Instrument) -> PriceInfo { values[instrument] ?? PriceInfo() }
    public var lastUpdate: Date? { values.values.compactMap { $0.lastSuccessAt }.max() }
}
