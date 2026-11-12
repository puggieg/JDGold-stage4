import Foundation

// 今日新高 / 新低提醒。纯函数：不读取当前时间、偏好、界面或网络，所有副作用交给 App 层。
// 基准与菜单里的「采集高 / 采集低」一致：本机今天（北京时间分日）实际采到的分钟报价极值。
public struct ExtremeAlertConfig: Equatable, Sendable {
    public var highEnabled: Bool
    public var lowEnabled: Bool
    public var instruments: Set<Instrument>
    public var cooldown: TimeInterval
    public var thresholdRatio: Double
    public init(highEnabled: Bool = false, lowEnabled: Bool = false, instruments: Set<Instrument> = [.icbc],
                cooldown: TimeInterval = 300, thresholdRatio: Double = 0.001) {
        self.highEnabled = highEnabled; self.lowEnabled = lowEnabled; self.instruments = instruments
        self.cooldown = cooldown.isFinite && cooldown > 0 ? cooldown : 300
        self.thresholdRatio = thresholdRatio.isFinite && thresholdRatio >= 0 ? thresholdRatio : 0.001
    }
}

// 一个冷静期窗口。startPrice 是本轮起点，lastRecord 是窗口内最后一个新纪录。
public struct ExtremeAlertStreak: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var startPrice: Double
    public var lastRecord: Double
    public var count: Int
    public init(startedAt: Date, startPrice: Double, lastRecord: Double, count: Int) {
        self.startedAt = startedAt; self.startPrice = startPrice; self.lastRecord = lastRecord; self.count = count
    }
}

// record 是今日采集高/低；anchor 是上次对外报过的价位，门槛以它为基准，
// 这样缓慢单边连涨也不会因为每次只涨一点点而永远不触发。
public struct ExtremeAlertDirectionState: Codable, Equatable, Sendable {
    public var record: Double?
    public var anchor: Double?
    public var streak: ExtremeAlertStreak?
    public init(record: Double? = nil, anchor: Double? = nil, streak: ExtremeAlertStreak? = nil) {
        self.record = record; self.anchor = anchor; self.streak = streak
    }
}

public struct ExtremeAlertInstrumentState: Codable, Equatable, Sendable {
    public var day: String
    public var high: ExtremeAlertDirectionState
    public var low: ExtremeAlertDirectionState
    public init(day: String) {
        self.day = day; self.high = ExtremeAlertDirectionState(); self.low = ExtremeAlertDirectionState()
    }
}

public struct ExtremeAlertState: Codable, Equatable, Sendable {
    public var instruments: [String: ExtremeAlertInstrumentState] = [:]
    public init() {}
}

public enum ExtremeAlertEngine {
    public static func evaluate(price: GoldPrices, history: TodayPriceHistory, config: ExtremeAlertConfig,
                                state: ExtremeAlertState, now: Date)
        -> (events: [AlertEvent], newState: ExtremeAlertState) {
        var next = state
        let day = MarketDay.key(now)
        var events: [AlertEvent] = []
        let validInstruments = Set(config.instruments.map { $0.rawValue })
        next.instruments = next.instruments.filter { validInstruments.contains($0.key) }
        for instrument in Instrument.allCases where validInstruments.contains(instrument.rawValue) {
            var item = next.instruments[instrument.rawValue] ?? ExtremeAlertInstrumentState(day: day)
            if item.day != day { item = ExtremeAlertInstrumentState(day: day) }
            let extremes = SparklineGeometry.extremes(history.samples(for: instrument, now: now))
            let info = price.priceInfo(for: instrument)
            let usable = !info.isStale && info.isValid && !MarketPresentation.isDelayed(info, now: now)
            let current: Double? = usable ? info.doublePrice : nil
            if config.highEnabled {
                evaluate(direction: &item.high, high: true, historyExtreme: extremes?.high, current: current,
                         instrument: instrument, config: config, now: now, events: &events)
            } else { item.high.streak = nil; item.high.anchor = item.high.record }
            if config.lowEnabled {
                evaluate(direction: &item.low, high: false, historyExtreme: extremes?.low, current: current,
                         instrument: instrument, config: config, now: now, events: &events)
            } else { item.low.streak = nil; item.low.anchor = item.low.record }
            next.instruments[instrument.rawValue] = item
        }
        return (events, next)
    }

    private static func evaluate(direction: inout ExtremeAlertDirectionState, high: Bool,
                                 historyExtreme: Double?, current: Double?, instrument: Instrument,
                                 config: ExtremeAlertConfig, now: Date, events: inout [AlertEvent]) {
        // 只用本地今日采集极值初始化或抬高 record；anchor 是「上次报过的价位」，
        // 不跟着历史极值走，否则每次只涨 0.05% 的慢牛会被门槛永远挡在外面。
        if let extreme = historyExtreme {
            if let record = direction.record { direction.record = high ? max(record, extreme) : min(record, extreme) }
            else { direction.record = extreme; direction.anchor = extreme }
        }
        // 今天第一个有效报价只建立基准，静默，避免一启动就同时报新高和新低。
        guard let record = direction.record else {
            if let current = current { direction.record = current; direction.anchor = current }
            direction.streak = nil
            return
        }
        if direction.anchor == nil { direction.anchor = record }
        let anchor = direction.anchor!
        var latest = record
        if let current = current, high ? current > record : current < record {
            let crosses = high ? current >= anchor * (1 + config.thresholdRatio)
                               : current <= anchor * (1 - config.thresholdRatio)
            if crosses {
                if direction.streak == nil {
                    // 首次破纪录：立即提醒一条。
                    let change = (current / anchor - 1) * 100
                    events.append(AlertEvent(kind: .breach, identity: identity(instrument, high: high),
                        title: "⚠️ 今日\(high ? "新高" : "新低"): \(instrument.displayName)",
                        body: "【\(instrument.displayName)】创今日采集\(high ? "新高" : "新低")\n" +
                              "当前价 \(format(current))\(unit(instrument))\n" +
                              "前纪录 \(format(anchor))\(unit(instrument))\n" +
                              "较前纪录 \(String(format: "%+.2f", change))%"))
                }
                if var streak = direction.streak { streak.count += 1; streak.lastRecord = current; direction.streak = streak }
                else {
                    direction.streak = ExtremeAlertStreak(startedAt: now, startPrice: anchor,
                                                          lastRecord: current, count: 1)
                }
                direction.anchor = current
            } else if var streak = direction.streak {
                // 冷静期内未过门槛的小幅刷新也累计，但不单独弹窗。
                streak.count += 1; streak.lastRecord = current; direction.streak = streak
            }
            latest = current
            direction.record = latest
        }
        // 冷静期结算：即使本轮行情无效也要结算，否则趋势停下来后状态会永远挂着。
        if let streak = direction.streak, now.timeIntervalSince(streak.startedAt) >= config.cooldown {
            if streak.count > 0 {
                let change = (streak.lastRecord / streak.startPrice - 1) * 100
                events.append(AlertEvent(kind: .breach, identity: identity(instrument, high: high),
                    title: "\(high ? "⤴" : "⤵") 持续\(high ? "创新高" : "创新低"): \(instrument.displayName)",
                    body: "【\(instrument.displayName)】近 \(Int(config.cooldown / 60)) 分钟持续\(high ? "创新高" : "创新低")，刷新纪录 \(streak.count) 次\n" +
                          "本轮累计 \(String(format: "%+.2f", change))%（\(format(streak.startPrice)) → \(format(streak.lastRecord))\(unit(instrument))）\n" +
                          "最新价 \(format(streak.lastRecord))\(unit(instrument))"))
                direction.streak = ExtremeAlertStreak(startedAt: now, startPrice: streak.lastRecord,
                                                      lastRecord: streak.lastRecord, count: 0)
                direction.anchor = streak.lastRecord
            } else {
                // 整整一个冷静期没有新纪录：视为本轮结束，回到可重新首报的状态。
                direction.streak = nil
                direction.anchor = latest
            }
        }
    }

    public static func identity(_ instrument: Instrument, high: Bool) -> String {
        "extreme_\(high ? "high" : "low")_\(instrument.rawValue)"
    }
    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func unit(_ instrument: Instrument) -> String { instrument.unit.isEmpty ? "" : " \(instrument.unit)" }
}
