import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DecisionFeatureSelfTests {
    private static let fixture = "var hq_str_fx_susdcny=\"23:33:01,6.6980000000,6.6988000000,6.6928000000,100.0000000000,6.6935000000,6.7014000000,6.6914000000,6.6988000000,在岸人民币,0.0896,0.0060,0.0100,此行情由新浪财经计算得出,0.0000,0.0000,,2026-10-14\";"
    private static let day = SourceTimestamp.sina(date: "2026-10-14", time: "23:33:01")!
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "汇率真实字段与非法响应", run: parseRate),
         SelfTestCase(name: "汇率失败退避恢复与防重入", run: { try blocking { try await rateService() } }),
         SelfTestCase(name: "溢价单位正负与反算", run: premiumFormula),
         SelfTestCase(name: "溢价缺失过期与边界降级", run: premiumMissing),
         SelfTestCase(name: "分钟合并与分钟内高低", run: minuteSamples),
         SelfTestCase(name: "历史持久化损坏与写入失败", run: { try blocking { try await historyFiles() } }),
         SelfTestCase(name: "北京时间跨日与一天容量", run: rollover),
         SelfTestCase(name: "走势平盘单点缺口与极值", run: geometry)]
    }
    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw SelfTestFailure(description: message) }
    }
    private static func close(_ a: Double, _ b: Double, tolerance: Double = 0.0000001) -> Bool { abs(a - b) <= tolerance }
    private static func quote(_ value: Double, at: Date = day) -> PriceInfo {
        var info = PriceInfo(price: String(value)); info.lastSuccessAt = at; info.sourceUpdatedAt = at; return info
    }
    private static func rate(at: Date = day) -> ExchangeRate { ExchangeRate(yuanPerDollar: 6.6988, sourceUpdatedAt: at, lastSuccessAt: at) }
    private static func parseRate() throws {
        let provider = SinaExchangeRateProvider()
        let parsed = try provider.parse(Data(fixture.utf8), fetchedAt: day)
        try check(parsed.yuanPerDollar == 6.6988 && parsed.sourceUpdatedAt == day && !parsed.isStale, "取 parts[8]/parts[17]/parts[0]")
        let request = try provider.makeRequest()
        try check(request.httpMethod == "GET" && request.url?.absoluteString == "https://hq.sinajs.cn/list=fx_susdcny", "公开 GET 接口")
        try check(request.value(forHTTPHeaderField: "Referer") == "https://finance.sina.com.cn", "请求头")
        let invalid = ["", "var hq_str_fx_susdcny=\"\";", fixture.replacingOccurrences(of: "fx_susdcny", with: "fx_susdcnh"),
            fixture.replacingOccurrences(of: "6.6988000000,在岸", with: "0,在岸"),
            fixture.replacingOccurrences(of: "6.6988000000,在岸", with: "NaN,在岸"),
            fixture.replacingOccurrences(of: "2026-10-14", with: "2026-02-30"), fixture.replacingOccurrences(of: "23:33:01", with: "99:33:01")]
        for sample in invalid {
            var rejected = false; do { _ = try provider.parse(Data(sample.utf8), fetchedAt: day) } catch { rejected = true }
            try check(rejected, "无效字段必须拒绝，不能回退昨收")
        }
    }
    private actor FakeRateClient: PriceHTTPClient {
        var failures = false
        var count = 0
        var paused = false
        var response: CheckedContinuation<Data, Error>?
        var started: CheckedContinuation<Void, Never>?
        init(paused: Bool = false) { self.paused = paused }
        func setFailure(_ value: Bool) { failures = value }
        func requests() -> Int { count }
        func data(for request: URLRequest) async throws -> Data {
            count += 1; started?.resume(); started = nil
            if failures { throw PriceError.invalidHTTP }
            if paused { return try await withCheckedThrowingContinuation { response = $0 } }
            return Data(DecisionFeatureSelfTests.fixture.utf8)
        }
        func waitUntilRequested() async { if count == 0 { await withCheckedContinuation { started = $0 } } }
        func resume() { response?.resume(returning: Data(DecisionFeatureSelfTests.fixture.utf8)); response = nil; paused = false }
    }
    private static func rateService() async throws {
        let client = FakeRateClient(); let service = ExchangeRateService(client: client)
        let first = await service.fetch(now: day)
        try check(first?.yuanPerDollar == 6.6988 && first?.isStale == false, "有效首价")
        await client.setFailure(true)
        let failed = await service.fetch(now: day.addingTimeInterval(1))
        try check(failed?.isStale == true, "失败立即失效")
        await client.setFailure(false)
        _ = await service.fetch(now: day.addingTimeInterval(2))
        let before = await client.requests(); try check(before == 2, "两秒退避未到期")
        let recovered = await service.fetch(now: day.addingTimeInterval(3))
        try check(recovered?.isStale == false && recovered?.lastSuccessAt == day.addingTimeInterval(3), "退避到期恢复")
        await client.setFailure(true)
        var now = day.addingTimeInterval(10)
        for seconds in [2.0,4,8,16,32,60,60] {
            _ = await service.fetch(now: now)
            let count = await client.requests()
            _ = await service.fetch(now: now.addingTimeInterval(seconds - 0.1))
            let skipped = await client.requests(); try check(skipped == count, "连续失败退避上限")
            now = now.addingTimeInterval(seconds)
        }
        let waiting = FakeRateClient(paused: true); let guarded = ExchangeRateService(client: waiting)
        let task = Task { await guarded.fetch(now: day) }
        await waiting.waitUntilRequested()
        _ = await guarded.fetch(now: day)
        let calls = await waiting.requests(); try check(calls == 1, "上一轮未结束不启动新请求")
        await waiting.resume(); _ = await task.value
    }
    private static func premiumFormula() throws {
        let london = quote(4100), domestic = quote(885)
        guard let value = PremiumCalculator.calculate(domestic: domestic, london: london, rate: rate(), now: day) else { throw SelfTestFailure(description: "有效数据不应隐藏") }
        try check(close(value.internationalYuanPerGram, 883.022167923224), "盎司转克与人民币单位")
        try check(close(value.yuanPerGram, 1.977832076776) && close(value.percent, 0.223984419488), "独立 Decimal 计算依据")
        try check(close((domestic.doublePrice - value.yuanPerGram) * 31.1035 / 6.6988, 4100), "由溢价反算伦敦金")
        try check(close((1 + value.percent / 100) * value.internationalYuanPerGram, domestic.doublePrice), "百分比以折算价为基准")
        try check(value.displayText == "溢价 +1.98 元/克（+0.2%）", "用户展示精度")
        let below = PremiumCalculator.calculate(domestic: quote(880), london: london, rate: rate(), now: day)!
        try check(below.yuanPerGram < 0 && below.percent < 0 && below.displayText.contains("-3.02"), "负溢价")
        let flat = PremiumCalculator.calculate(domestic: quote(value.internationalYuanPerGram), london: london, rate: rate(), now: day)!
        try check(flat.displayText == "溢价 +0.00 元/克（+0.0%）", "零值不出现负零")
    }
    private static func premiumMissing() throws {
        let domestic = quote(885), london = quote(4100)
        var stale = rate(); stale.isStale = true
        var oldPrice = domestic; oldPrice.isStale = true
        let invalidRates: [ExchangeRate?] = [nil, stale, ExchangeRate(yuanPerDollar: 0, sourceUpdatedAt: day, lastSuccessAt: day),
            ExchangeRate(yuanPerDollar: .nan, sourceUpdatedAt: day, lastSuccessAt: day), rate(at: day.addingTimeInterval(-300)), rate(at: day.addingTimeInterval(61))]
        for fx in invalidRates { try check(PremiumCalculator.calculate(domestic: domestic, london: london, rate: fx, now: day) == nil, "缺失/失败/过期/未来汇率不能计算") }
        for bad in [PriceInfo(), quote(0), quote(-1), quote(.infinity), oldPrice, quote(885, at: day.addingTimeInterval(-300))] {
            try check(PremiumCalculator.calculate(domestic: bad, london: london, rate: rate(), now: day) == nil, "非法国内价")
            try check(PremiumCalculator.calculate(domestic: domestic, london: bad, rate: rate(), now: day) == nil, "非法伦敦价")
        }
        try check(PremiumCalculator.calculate(domestic: domestic, london: london, rate: rate(at: day.addingTimeInterval(-299)), now: day) != nil, "时效边界前仍可用")
        try check(PremiumCalculator.calculate(domestic: domestic, london: quote(Double.greatestFiniteMagnitude), rate: rate(), now: day) == nil, "乘法溢出不能画数字")
    }
    private static func minuteSamples() throws {
        var history = TodayPriceHistory(day: MarketDay.key(day))
        for (offset, price) in [(0.0,1000.0),(9,1002),(19,999),(29,1001)] {
            let time = day.addingTimeInterval(offset)
            history = TodayPriceHistory.recording(GoldPrices(values: [.minsheng: quote(price, at: time)]), in: history, now: time)
        }
        let sample = history.values[.minsheng]!.first!
        try check(history.values[.minsheng]?.count == 1 && sample.price == 1001 && sample.high == 1002 && sample.low == 999, "一分钟一条并保留全部采集高低")
        let next = day.addingTimeInterval(60)
        history = TodayPriceHistory.recording(GoldPrices(values: [.minsheng: quote(1003, at: next), .london: quote(4000, at: next)]), in: history, now: next)
        try check(history.values[.minsheng]?.count == 2 && history.values[.london]?.count == 1, "分钟桶与品种隔离")
        var stale = quote(2000, at: next); stale.isStale = true
        let ignored = TodayPriceHistory.recording(GoldPrices(values: [.minsheng: stale, .icbc: PriceInfo()]), in: history, now: next)
        try check(ignored == history, "失败缓存不伪造新点")
        let extremes = SparklineGeometry.extremes(history.values[.minsheng]!)!
        try check(extremes.high == 1003 && extremes.low == 999, "高低包含分钟内曾出现的价格")
    }
    private static func historyFiles() async throws {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JDGold_SELFTEST_TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("JDGold-history-selftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("today-prices.json")
        let store = TodayHistoryStore(fileURL: file)
        _ = await store.record(GoldPrices(values: [.minsheng: quote(1000)]), now: day)
        let firstBytes = try Data(contentsOf: file)
        let later = day.addingTimeInterval(10)
        _ = await store.record(GoldPrices(values: [.minsheng: quote(1002, at: later)]), now: later)
        try check(try Data(contentsOf: file) == firstBytes, "同分钟不反复写盘")
        await store.flush(now: later)
        let reload = TodayHistoryStore(fileURL: file)
        let restored = await reload.snapshot(now: later)
        try check(restored.values[.minsheng]?.first?.price == 1002 && restored.values[.minsheng]?.count == 1, "退出补写与同日重启恢复")
        let nextDay = day.addingTimeInterval(86400)
        let cleared = await reload.snapshot(now: nextDay)
        try check(cleared.values.isEmpty && cleared.day == "2026-10-15", "跨日清空")
        let archived = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        try check(archived["day"] as? String == "2026-10-15" && (archived["prices"] as? [String: Any])?.isEmpty == true, "清空也写回磁盘")
        try Data("corrupt history".utf8).write(to: file)
        let broken = TodayHistoryStore(fileURL: file); let empty = await broken.snapshot(now: day)
        try check(empty.values.isEmpty, "损坏文件显示无样本")
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("unreadable-") }
        try check(backups.count == 1 && (try Data(contentsOf: backups[0])) == Data("corrupt history".utf8), "原文件备份")
        let blocker = directory.appendingPathComponent("blocker"); try Data("file".utf8).write(to: blocker)
        let cannotWrite = TodayHistoryStore(fileURL: blocker.appendingPathComponent("today.json"))
        let memory = await cannotWrite.record(GoldPrices(values: [.minsheng: quote(1000)]), now: day)
        try check(memory.values[.minsheng]?.count == 1, "写盘失败仍保留内存记录")
    }
    private static func rollover() throws {
        let end = SourceTimestamp.sina(date: "2026-12-31", time: "23:59:59")!
        var history = TodayPriceHistory.recording(GoldPrices(values: [.minsheng: quote(1000, at: end)]), in: TodayPriceHistory(day: MarketDay.key(end)), now: end)
        let next = end.addingTimeInterval(1)
        try check(history.samples(for: .minsheng, now: next).isEmpty, "跨年立即隐藏昨日线")
        history = TodayPriceHistory.recording(GoldPrices(), in: history, now: next)
        try check(history.day == "2027-01-01" && history.values.isEmpty, "跨年清理")
        let midnight = SourceTimestamp.sina(date: "2026-10-14", time: "00:00:00")!
        let all = (0..<1440).map { index -> MinutePriceSample in
            let time = midnight.addingTimeInterval(Double(index) * 60)
            return MinutePriceSample(minute: time, observedAt: time, price: Double(index) + 1000)
        }
        history = TodayPriceHistory(day: MarketDay.key(midnight), values: [.minsheng: all])
        let finalMinute = midnight.addingTimeInterval(86390)
        history = TodayPriceHistory.recording(GoldPrices(values: [.minsheng: quote(2000, at: finalMinute)]), in: history, now: finalMinute)
        try check(history.values[.minsheng]?.count == 1440 && Set(history.values[.minsheng]!.map { $0.minute }).count == 1440, "最多一天分钟数")
    }
    private static func geometry() throws {
        func sample(_ offset: Double, _ value: Double) -> MinutePriceSample {
            let time = MarketDay.minute(day.addingTimeInterval(offset))
            return MinutePriceSample(minute: time, observedAt: time, price: value)
        }
        try check(SparklineGeometry.points([]).isEmpty, "无样本")
        let one = SparklineGeometry.points([sample(0, 1000)])
        try check(one.count == 1 && one[0].x == 0.5 && one[0].y == 0.5, "单点居中")
        let flat = SparklineGeometry.points([sample(0,1000),sample(60,1000)])
        try check(flat.allSatisfy { $0.y == 0.5 && $0.x.isFinite }, "平盘不除以零")
        let gapped = SparklineGeometry.points([sample(0,1000),sample(60,1001),sample(600,999)])
        try check(gapped.map { $0.startsSegment } == [true,false,true] && close(gapped[1].x,0.1), "横轴按真实时间，缺口断线")
        try check(gapped.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "坐标有界")
        let extreme = SparklineGeometry.points([sample(0,Double.leastNormalMagnitude),sample(60,Double.greatestFiniteMagnitude)])
        try check(extreme.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "极端数字不产生 NaN")
        try check(SparklineGeometry.points([MinutePriceSample(minute: day, observedAt: day, price: .nan)]).isEmpty, "非法点不画")
    }
    private final class FailureBox: @unchecked Sendable {
        private let lock = NSLock(); private var error: Error?
        func record(_ error: Error) { lock.lock(); self.error = error; lock.unlock() }
        func verify() throws { lock.lock(); let saved = error; lock.unlock(); if let saved = saved { throw saved } }
    }
    private static func blocking(_ run: @escaping @Sendable () async throws -> Void) throws {
        let completed = DispatchSemaphore(value: 0); let box = FailureBox()
        let task = Task.detached { do { try await run() } catch { box.record(error) }; completed.signal() }
        guard completed.wait(timeout: .now() + 30) == .success else { task.cancel(); throw SelfTestFailure(description: "阶段四模拟服务测试超时") }
        try box.verify()
    }
}
