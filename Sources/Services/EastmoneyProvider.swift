import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct EastmoneyProvider: PriceProvider {
    public init() {}
    public let source = MarketSource.eastmoney
    public let instruments: [Instrument] = [.usdIndex]
    private struct Response: Decodable {
        struct Values: Decodable { var f43: Int?; var f60: Int?; var f169: Int?; var f170: Int? }
        var data: Values?
    }
    public func makeRequest() throws -> URLRequest {
        var request = URLRequest(url: try PriceParsing.url("https://push2.eastmoney.com/api/qt/stock/get?secid=100.UDI&fields=f43,f57,f58,f60,f169,f170"))
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent"); return request
    }
    public func parse(_ data: Data) throws -> ProviderResult {
        guard let values = try PriceParsing.decodeJSON(Response.self, data: data).data, let price = values.f43 else { throw PriceError.invalidPayload }
        var info = PriceInfo(price: PriceParsing.number(Double(price) / 100, precision: Instrument.usdIndex.precision))
        if let raw = values.f60 { info.yesterdayPrice = PriceParsing.number(Double(raw) / 100) }
        if let raw = values.f169 { info.changeAmount = (raw >= 0 ? "+" : "") + PriceParsing.number(Double(raw) / 100) }
        if let raw = values.f170 { info.changeRate = (raw >= 0 ? "+" : "") + PriceParsing.number(Double(raw) / 100) + "%" }
        return ProviderResult(prices: [.usdIndex: info])
    }
}
