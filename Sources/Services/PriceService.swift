import Foundation

// actor 保护缓存；请求并发，缓存保留、验证和退避只在这里实现一次。
public actor PriceService {
    private let providers: [any PriceProvider]
    private let client: any PriceHTTPClient
    private let log: @Sendable (String, String) -> Void
    private var cache: [Instrument: PriceInfo] = [:]
    private var failures: [MarketSource: Int] = [:]
    private var retryAfter: [MarketSource: Date] = [:]
    private var fetching = false
    public init(providers: [any PriceProvider] = [MinshengProvider(), ICBCProvider(), ZheshangProvider(), SinaProvider(), EastmoneyProvider()],
                client: any PriceHTTPClient = HTTPClient(), log: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.providers = providers; self.client = client; self.log = log
    }
    private struct Fetched: Sendable { var provider: any PriceProvider; var result: ProviderResult?; var error: String? }
    public func fetchAllPrices(now: Date? = nil) async -> GoldPrices {
        guard !fetching else { return GoldPrices(values: cache) }
        fetching = true; defer { fetching = false }
        var snapshot = cache.mapValues { info -> PriceInfo in var old = info; old.isStale = true; return old }
        let startedAt = now ?? Date()
        let eligible = providers.filter { startedAt >= (retryAfter[$0.source] ?? .distantPast) }
        let client = self.client
        await withTaskGroup(of: Fetched.self) { group in
            for provider in eligible {
                group.addTask {
                    do {
                        let data = try await client.data(for: provider.makeRequest())
                        return Fetched(provider: provider, result: try provider.parse(data), error: nil)
                    } catch { return Fetched(provider: provider, result: nil, error: String(describing: error)) }
                }
            }
            for await fetched in group {
                let finishedAt = now ?? Date()
                var complete = fetched.error == nil
                for instrument in fetched.provider.instruments {
                    if var info = fetched.result?.prices[instrument], info.isValid {
                        info.isStale = false; info.lastSuccessAt = finishedAt
                        let old = cache[instrument]
                        info.lastPriceChangeAt = old?.doublePrice == info.doublePrice ? (old?.lastPriceChangeAt ?? finishedAt) : finishedAt
                        cache[instrument] = info; snapshot[instrument] = info
                    } else {
                        complete = false
                        var old = cache[instrument] ?? PriceInfo(); old.isStale = true
                        snapshot[instrument] = old
                    }
                }
                if complete { failures[fetched.provider.source] = nil; retryAfter[fetched.provider.source] = nil }
                else {
                    let count = min((failures[fetched.provider.source] ?? 0) + 1, 6)
                    failures[fetched.provider.source] = count
                    let delay = RetryPolicy.delay(failures: count)
                    retryAfter[fetched.provider.source] = finishedAt.addingTimeInterval(delay)
                    log(fetched.provider.source.rawValue, "请求失败；\(Int(delay)) 秒后允许重试：\(fetched.error ?? "响应缺少有效行情")")
                }
            }
        }
        return GoldPrices(values: snapshot)
    }
}
