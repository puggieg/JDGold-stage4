import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// 假客户端只返回本地数据，覆盖缓存和退避，不访问真实接口。
public enum ServiceSelfTests {
    private actor FakeClient: PriceHTTPClient {
        enum Mode { case success, failICBC, partialSina }
        var mode = Mode.success
        var counts: [String: Int] = [:]
        func setMode(_ value: Mode) { mode = value }
        func count(_ path: String) -> Int { counts[path] ?? 0 }
        func data(for request: URLRequest) async throws -> Data {
            let path = request.url!.path
            counts[path, default: 0] += 1
            if mode == .failICBC && path.contains("icbcLatestPrice") { throw PriceError.invalidHTTP }
            if request.url?.host == "hq.sinajs.cn" {
                let london = "var hq_str_hf_XAU=\"1000,,0,0,0,0,12:00:00,999\";"
                let newyork = "var hq_str_hf_GC=\"2000,,0,0,0,0,12:00:00,1999\";"
                return Data((mode == .partialSina ? london : london + newyork).utf8)
            }
            if request.url?.host == "push2.eastmoney.com" {
                return Data("{\"data\":{\"f43\":10000,\"f60\":10000,\"f169\":0,\"f170\":0}}".utf8)
            }
            return Data("{\"resultData\":{\"datas\":{\"price\":\"1000\",\"yesterdayPrice\":\"999\",\"upAndDownRate\":\"+0.10%\",\"upAndDownAmt\":\"1\"}}}".utf8)
        }
    }
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?
        func record(_ error: Error) { lock.lock(); self.error = error; lock.unlock() }
        func check() throws {
            lock.lock(); let saved = error; lock.unlock()
            if let saved = saved { throw saved }
        }
    }
    // 两种测试入口共用；后台执行 actor 测试，主线程不需要运行 AppKit 循环。
    public static func runBlocking() throws {
        let completed = DispatchSemaphore(value: 0)
        let result = ResultBox()
        let task = Task.detached {
            do { try await run() } catch { result.record(error) }
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 30) == .success else {
            task.cancel(); throw SelfTestFailure(description: "假网络测试超时")
        }
        try result.check()
    }
    public static func run() async throws {
        let client = FakeClient(); let service = PriceService(client: client)
        let start = Date(timeIntervalSince1970: 1000)
        let first = await service.fetchAllPrices(now: start)
        try check(first.values.count == 6 && first.values.values.allSatisfy { !$0.isStale && $0.lastSuccessAt == start }, "首次有效缓存")
        try check(first.values.values.allSatisfy { $0.lastPriceChangeAt == start }, "记录首次有效变价时间")
        await client.setMode(.failICBC)
        let failed = await service.fetchAllPrices(now: start.addingTimeInterval(10))
        try check(failed.priceInfo(for: .icbc).isStale && failed.priceInfo(for: .icbc).price == "1000", "失败保留价格")
        try check(failed.priceInfo(for: .icbc).lastSuccessAt == start && !failed.priceInfo(for: .minsheng).isStale, "保留时间且隔离其他源")
        let path = "/gw2/generic/jrm/h5/m/icbcLatestPrice"
        let before = await client.count(path)
        await client.setMode(.success)
        let skipped = await service.fetchAllPrices(now: start.addingTimeInterval(11))
        let after = await client.count(path)
        try check(skipped.priceInfo(for: .icbc).isStale && before == after, "退避期跳过请求")
        let recovered = await service.fetchAllPrices(now: start.addingTimeInterval(12))
        try check(!recovered.priceInfo(for: .icbc).isStale, "退避到期恢复")
        try check(recovered.priceInfo(for: .icbc).lastPriceChangeAt == start, "相同报价不更新变价时间")
        await client.setMode(.partialSina)
        let partial = await service.fetchAllPrices(now: start.addingTimeInterval(20))
        try check(!partial.priceInfo(for: .london).isStale && partial.priceInfo(for: .newyork).isStale, "新浪两个品种独立缓存")
        try check(partial.priceInfo(for: .newyork).lastSuccessAt == recovered.priceInfo(for: .newyork).lastSuccessAt, "部分失败不改时间")
        try check((1...9).map { RetryPolicy.delay(failures: $0) } == [2,4,8,16,32,60,60,60,60], "退避上限")
    }
    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw SelfTestFailure(description: message) }
    }
}
