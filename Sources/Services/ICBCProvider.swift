import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct ICBCProvider: PriceProvider {
    public init() {}
    public let source = MarketSource.icbc
    public let instruments: [Instrument] = [.icbc]
    public func makeRequest() throws -> URLRequest { try BankPriceParsing.post(url: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/icbcLatestPrice?productSku=2005453243", sku: "2005453243") }
    public func parse(_ data: Data) throws -> ProviderResult { try BankPriceParsing.parse(data, instrument: .icbc) }
}
