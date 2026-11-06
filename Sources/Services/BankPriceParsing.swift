import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// 三家银行共享 JSON 解析、POST 构造；每个 Provider 只描述自己的端点及品种。
enum BankPriceParsing {
    private struct Response: Decodable {
        struct Result: Decodable {
            struct Values: Decodable { var price: String?; var yesterdayPrice: String?; var upAndDownRate: String?; var upAndDownAmt: String?; var time: String? }
            var datas: Values?
        }
        var resultData: Result?
    }
    static func parse(_ data: Data, instrument: Instrument) throws -> ProviderResult {
        let response = try PriceParsing.decodeJSON(Response.self, data: data)
        guard let values = response.resultData?.datas else { throw PriceError.invalidPayload }
        var info = PriceInfo(price: values.price ?? "--", yesterdayPrice: values.yesterdayPrice ?? "--",
            changeRate: values.upAndDownRate ?? "", changeAmount: values.upAndDownAmt ?? "")
        // 真实 curl 中 datas.time 是毫秒字符串；仅解析现有响应，不增加参数。
        info.sourceUpdatedAt = SourceTimestamp.milliseconds(values.time)
        return ProviderResult(prices: [instrument: info])
    }
    static func post(url: String, sku: String) throws -> URLRequest {
        var request = URLRequest(url: try PriceParsing.url(url))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["reqData": ["productSku": sku]])
        return request
    }
}
