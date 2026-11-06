import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SinaExchangeRateProvider: Sendable {
    public init() {}
    public func makeRequest() throws -> URLRequest {
        var request = URLRequest(url: try PriceParsing.url("https://hq.sinajs.cn/list=fx_susdcny"))
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        return request
    }
    // 2026-10-14 先真实 curl，再编写解析；完整依据见 verification/FX_API.md。
    // curl -H 'Referer: https://finance.sina.com.cn' 'https://hq.sinajs.cn/list=fx_susdcny'
    // var hq_str_fx_susdcny="23:33:01,6.6980000000,6.6988000000,6.6928000000,100.0000000000,6.6935000000,6.7014000000,6.6914000000,6.6988000000,在岸人民币,0.0896,0.0060,0.0100,此行情由新浪财经计算得出,0.0000,0.0000,,2026-10-14";
    // 新浪 sf_sdk.js 的 forex 分支：price=Number(i[8])，fx_ 日期索引 s=17，时间 i[0]。
    // 不照搬其“价格为零时用昨收回退”的逻辑，避免显示错误溢价。
    public func parse(_ data: Data, fetchedAt: Date) throws -> ExchangeRate {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb),
              let line = text.components(separatedBy: ";").first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("var hq_str_fx_susdcny=") }),
              let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last else { throw PriceError.invalidPayload }
        let parts = String(line[line.index(after: first)..<last]).components(separatedBy: ",")
        guard parts.count >= 18, let rate = Double(parts[8]), rate.isFinite, rate > 0,
              let source = SourceTimestamp.sina(date: parts[17], time: parts[0]) else { throw PriceError.invalidPayload }
        return ExchangeRate(yuanPerDollar: rate, sourceUpdatedAt: source, lastSuccessAt: fetchedAt)
    }
}

public actor ExchangeRateService {
    private let provider: SinaExchangeRateProvider
    private let client: any PriceHTTPClient
    private let log: @Sendable (String, String) -> Void
    private var cached: ExchangeRate?
    private var failures = 0
    private var retryAfter = Date.distantPast
    private var fetching = false
    public init(provider: SinaExchangeRateProvider = SinaExchangeRateProvider(), client: any PriceHTTPClient = HTTPClient(),
                log: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.provider = provider; self.client = client; self.log = log
    }
    public func fetch(now: Date? = nil) async -> ExchangeRate? {
        let started = now ?? Date()
        guard !fetching, started >= retryAfter else { return cached }
        fetching = true; defer { fetching = false }
        do {
            let data = try await client.data(for: provider.makeRequest())
            let rate = try provider.parse(data, fetchedAt: now ?? Date())
            cached = rate; failures = 0; retryAfter = .distantPast
        } catch {
            failures = min(failures + 1, 6)
            let delay = RetryPolicy.delay(failures: failures)
            retryAfter = (now ?? Date()).addingTimeInterval(delay)
            // 缓存仅用于诊断，失败立即标过期，不能拿上次汇率继续显示溢价。
            cached?.isStale = true
            log("美元兑人民币", "请求或解析失败；\(Int(delay)) 秒后重试，错误代码 \((error as NSError).code)")
        }
        return cached
    }
}
