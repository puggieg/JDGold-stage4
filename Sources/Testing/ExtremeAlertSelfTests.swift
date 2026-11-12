import Foundation

// 阶段五：新高/新低提醒的边界断言，与 --selftest / XCTest 共用，不访问真实行情或偏好。
public enum ExtremeAlertSelfTests {
    private static let day = Date(timeIntervalSince1970: 43200) // 北京时间 1970-01-01 20:00
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "新高首报与冷静期汇总", run: firstAndCooldown),
         SelfTestCase(name: "幅度门槛与缓慢单边上涨", run: threshold),
         SelfTestCase(name: "新高与新低方向独立", run: directions),
         SelfTestCase(name: "开关关闭与重新启用", run: toggles),
         SelfTestCase(name: "跨日重置与无效行情", run: rolloverAndInvalid),
         SelfTestCase(name: "品种多选与纯函数", run: instrumentsAndPurity),
         SelfTestCase(name: "免打扰路由与状态持久化", run: routingAndStore)]
    }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestFailure(description: message) }
    }
    private static func config(high: Bool = true, low: Bool = false, instruments: Set<Instrument> = [.icbc],
                               cooldown: TimeInterval = 300, ratio: Double = 0.001) -> ExtremeAlertConfig {
        ExtremeAlertConfig(highEnabled: high, lowEnabled: low, instruments: instruments,
                           cooldown: cooldown, thresholdRatio: ratio)
    }
    private static func run(_ value: Double, at: Date, history: TodayPriceHistory = TodayPriceHistory(day: MarketDay.key(day)),
                            config: ExtremeAlertConfig, state: ExtremeAlertState,
                            instrument: Instrument = .icbc) -> (events: [AlertEvent], newState: ExtremeAlertState) {
        var info = PriceInfo(price: String(value))
        info.sourceUpdatedAt = at; info.lastPriceChangeAt = at; info.lastSuccessAt = at
        let result = ExtremeAlertEngine.evaluate(price: GoldPrices(values: [instrument: info]), history: history,
                                                 config: config, state: state, now: at)
        return (result.events, result.newState)
    }
    private static func history(_ highs: [Double], at: Date) -> TodayPriceHistory {
        let samples = highs.enumerated().map { index, high -> MinutePriceSample in
            let minute = MarketDay.minute(at.addingTimeInterval(Double(index) * 60))
            return MinutePriceSample(minute: minute, observedAt: minute, price: high, high: high, low: high)
        }
        return TodayPriceHistory(day: MarketDay.key(at), values: [.icbc: samples])
    }
    private static func icbc(_ state: ExtremeAlertState) -> ExtremeAlertInstrumentState? { state.instruments["icbc"] }

    private static func firstAndCooldown() throws {
        let cfg = config()
        let first = run(1000, at: day, config: cfg, state: ExtremeAlertState())
        try check(first.events.isEmpty, "今日第一个有效报价只建立基准")
        try check(icbc(first.newState)?.high.record == 1000, "基准为首个报价")
        let alert = run(1002, at: day.addingTimeInterval(10), config: cfg, state: first.newState)
        try check(alert.events.count == 1 && alert.events[0].body.contains("创今日采集新高"), "首次破纪录立即一条")
        try check(alert.events[0].body.contains("+0.20%"), "首报写明相对前纪录涨幅")
        let same = run(1002, at: day.addingTimeInterval(20), config: cfg, state: alert.newState)
        try check(same.events.isEmpty, "同价不重复")
        let pullback = run(1001, at: day.addingTimeInterval(30), config: cfg, state: same.newState)
        try check(pullback.events.isEmpty, "回落不报新高")
        let more = run(1003, at: day.addingTimeInterval(40), config: cfg, state: pullback.newState)
        try check(more.events.isEmpty, "冷静期内再创新高只静默累计")
        let due = run(1003, at: day.addingTimeInterval(310), config: cfg, state: more.newState)
        try check(due.events.count == 1 && due.events[0].body.contains("刷新纪录 2 次"), "期满合并为一条汇总")
        try check(due.events[0].body.contains("+0.30%"), "汇总写明本轮累计幅度")
        try check(due.events[0].title.hasPrefix("⤴"), "持续创新高保留向上箭头")
        let quietWindow = run(1003, at: day.addingTimeInterval(620), config: cfg, state: due.newState)
        try check(quietWindow.events.isEmpty, "一整个冷静期无新纪录不再发汇总")
        let restart = run(1005, at: day.addingTimeInterval(630), config: cfg, state: quietWindow.newState)
        try check(restart.events.count == 1 && restart.events[0].body.contains("创今日采集新高"), "趋势结束后重新首报")
    }
    private static func threshold() throws {
        let cfg = config()
        let seed = run(1000, at: day, config: cfg, state: ExtremeAlertState())
        let tiny = run(1000.5, at: day.addingTimeInterval(10), config: cfg, state: seed.newState)
        try check(tiny.events.isEmpty, "0.05% 抖动不提醒")
        // 历史极值已经抬到 1000.5，anchor 仍应停在 1000，慢牛不能被门槛永久挡住。
        let slow = run(1001.2, at: day.addingTimeInterval(20), history: history([1000.5], at: day),
                       config: cfg, state: tiny.newState)
        try check(slow.events.count == 1 && slow.events[0].body.contains("+0.12%"), "缓慢连涨累计过门槛后仍会首报")
        let zero = config(ratio: 0)
        let noThreshold = run(1000.1, at: day.addingTimeInterval(10), config: zero, state: seed.newState)
        try check(noThreshold.events.count == 1, "门槛设为 0 时任何新纪录都报")
    }
    private static func directions() throws {
        let cfg = config(high: true, low: true)
        let seed = run(1000, at: day, config: cfg, state: ExtremeAlertState())
        try check(seed.events.isEmpty, "同一报价不会同时报新高和新低")
        let up = run(1002, at: day.addingTimeInterval(10), config: cfg, state: seed.newState)
        try check(up.events.count == 1 && up.events[0].body.contains("新高"), "只报新高")
        let down = run(998, at: day.addingTimeInterval(20), config: cfg, state: up.newState)
        try check(down.events.count == 1 && down.events[0].body.contains("新低"), "方向反转时新低独立立即首报")
        try check(icbc(down.newState)?.high.streak != nil && icbc(down.newState)?.low.streak != nil, "两个方向各自计时")
        try check(icbc(down.newState)?.high.record == 1002 && icbc(down.newState)?.low.record == 998, "两个方向各自记录极值")
        // 两个方向的冷静期都到期时，汇总标题的箭头要各自符合方向。
        let summaries = run(997, at: day.addingTimeInterval(321), config: cfg, state: down.newState).events
        try check(summaries.contains { $0.title.hasPrefix("⤵") && $0.title.contains("创新低") }, "持续创新低用向下箭头")
        try check(!summaries.contains { $0.title.contains("创新低") && $0.title.hasPrefix("⤴") }, "新低不能再用向上箭头")
        try check(summaries.contains { $0.title.hasPrefix("⤴") && $0.title.contains("创新高") }, "持续创新高仍是向上箭头")
    }
    private static func toggles() throws {
        let off = config(high: false, low: true)
        let seed = run(1000, at: day, config: off, state: ExtremeAlertState())
        let ignored = run(1005, at: day.addingTimeInterval(10), config: off, state: seed.newState)
        try check(ignored.events.isEmpty, "关闭新高后不提醒")
        try check(icbc(ignored.newState)?.high.streak == nil, "关闭方向清除冷静期")
        let on = config()
        let reenabled = run(1005, at: day.addingTimeInterval(20), config: on, state: ignored.newState)
        try check(reenabled.events.isEmpty, "重新启用不补报关闭期间的旧纪录")
        let fresh = run(1008, at: day.addingTimeInterval(30), config: on, state: reenabled.newState)
        try check(fresh.events.count == 1, "重新启用后的新纪录正常首报")
    }
    private static func rolloverAndInvalid() throws {
        let cfg = config()
        let seed = run(1000, at: day, config: cfg, state: ExtremeAlertState())
        let alert = run(1002, at: day.addingTimeInterval(10), config: cfg, state: seed.newState)
        let tomorrow = day.addingTimeInterval(86400)
        let next = run(1002, at: tomorrow, config: cfg, state: alert.newState)
        try check(next.events.isEmpty && icbc(next.newState)?.day == MarketDay.key(tomorrow), "跨北京时间零点重置")
        try check(icbc(next.newState)?.high.record == 1002 && icbc(next.newState)?.high.streak == nil, "新日重新建立基准")
        var stale = PriceInfo(price: "9999"); stale.isStale = true
        let invalid = ExtremeAlertEngine.evaluate(price: GoldPrices(values: [.icbc: stale]),
            history: TodayPriceHistory(day: MarketDay.key(day)), config: cfg, state: alert.newState, now: day.addingTimeInterval(310))
        try check(invalid.events.count == 1 && invalid.events[0].body.contains("持续"), "无效行情仍结算冷静期汇总")
        try check(icbc(invalid.newState)?.high.record == 1002, "失败缓存不冒充新纪录")
    }
    private static func instrumentsAndPurity() throws {
        let other = config(high: true, low: false, instruments: [.minsheng])
        let seed = run(1000, at: day, config: other, state: ExtremeAlertState())
        let ignored = run(1002, at: day.addingTimeInterval(10), config: other, state: seed.newState)
        try check(ignored.events.isEmpty && ignored.newState.instruments["icbc"] == nil, "未勾选品种不监控")
        let cfg = config()
        var original = ExtremeAlertState()
        original.instruments["icbc"] = ExtremeAlertInstrumentState(day: MarketDay.key(day))
        original.instruments["icbc"]?.high = ExtremeAlertDirectionState(record: 1000, anchor: 1000)
        let a = ExtremeAlertEngine.evaluate(price: GoldPrices(values: [.icbc: PriceInfo(price: "1002")]),
            history: TodayPriceHistory(day: MarketDay.key(day)), config: cfg, state: original, now: day)
        let b = ExtremeAlertEngine.evaluate(price: GoldPrices(values: [.icbc: PriceInfo(price: "1002")]),
            history: TodayPriceHistory(day: MarketDay.key(day)), config: cfg, state: original, now: day)
        try check(a.events == b.events && a.newState == b.newState, "确定性")
        try check(original.instruments["icbc"]?.high.anchor == 1000 && original.instruments["icbc"]?.high.streak == nil, "不修改输入状态")
        let bad = ExtremeAlertConfig(highEnabled: true, instruments: [.icbc], cooldown: -1, thresholdRatio: .nan)
        try check(bad.cooldown == 300 && bad.thresholdRatio == 0.001, "非法配置回退到安全默认值")
    }
    private static func routingAndStore() throws {
        var state = AlertState()
        state.quietHours = QuietHours(enabled: true, startMinute: 0, endMinute: 1440 - 1, timeZoneIdentifier: "UTC")
        let events = [AlertEvent(kind: .breach, identity: ExtremeAlertEngine.identity(.icbc, high: true),
                                 title: "今日新高", body: "测试")]
        let routed = AlertEngine.routeAll(events, state: &state, now: day)
        try check(routed.count == 1 && routed[0].delivery == .recordOnly, "免打扰期间只记录")
        try check(state.pending.count == 1, "待汇总保留新高新低记录")
        let suite = "JDGold.ExtremeSelftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExtremeAlertStore(defaults: defaults)
        var saved = ExtremeAlertState()
        saved.instruments["icbc"] = ExtremeAlertInstrumentState(day: "1970-01-01")
        saved.instruments["icbc"]?.high.record = 1002
        store.save(saved)
        try check(store.load() == saved, "状态写入读回一致")
        defaults.set(Data("broken".utf8), forKey: ExtremeAlertStore.stateKey)
        try check(store.load().instruments.isEmpty, "损坏状态从空开始")
    }
}
