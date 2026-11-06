import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct MinshengProvider: PriceProvider {
    public init() {}
    public let source = MarketSource.minsheng
    public let instruments: [Instrument] = [.minsheng]
    public func makeRequest() throws -> URLRequest { URLRequest(url: try PriceParsing.url("https://api.jdjygold.com/gw/generic/hj/h5/m/latestPrice")) }
    public func parse(_ data: Data) throws -> ProviderResult { try BankPriceParsing.parse(data, instrument: .minsheng) }
}
