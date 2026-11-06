import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct ZheshangProvider: PriceProvider {
    public init() {}
    public let source = MarketSource.zheshang
    public let instruments: [Instrument] = [.zheshang]
    public func makeRequest() throws -> URLRequest { try BankPriceParsing.post(url: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=1961543816", sku: "1961543816") }
    public func parse(_ data: Data) throws -> ProviderResult { try BankPriceParsing.parse(data, instrument: .zheshang) }
}
