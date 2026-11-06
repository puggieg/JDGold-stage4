import Foundation

// 纯函数：不读取当前时间、偏好、界面或网络；所有副作用交给 App 层。
public enum AlertEngine {
    public static func evaluate(price: GoldPrices, rules: [AlertRule], state: AlertState, now: Date)
        -> (events: [AlertEvent], newState: AlertState) {
        var next = state
        next.targetUpdates.removeAll()
        var events: [AlertEvent] = []
        flushPending(state: &next, now: now, events: &events)
        let liveIDs = Set(rules.map { $0.id })
        next.rules = next.rules.filter { liveIDs.contains($0.key) }
        let valid = rules.filter { $0.enabled && $0.isValid }
        let buffer = state.bufferRatio.isFinite && (0..<1).contains(state.bufferRatio) ? state.bufferRatio : 0.001
        for instrument in Instrument.allCases {
            let info = price.priceInfo(for: instrument)
            guard !info.isStale, info.isValid else { continue }
            for direction in AlertDirection.allCases {
                // 旧档位通知顺序保持不变，避免删除后重新添加导致顺序变化。
                let matching = valid.filter { $0.instrument == instrument && $0.direction == direction }
                    .enumerated().sorted {
                        let a = $0.element.legacySlot ?? Int.max
                        let b = $1.element.legacySlot ?? Int.max
                        return a == b ? $0.offset < $1.offset : a < b
                    }.map { $0.element }
                var newlyBreached: [AlertRule] = []
                for rule in matching {
                    var runtime = next.rules[rule.id] ?? RuleRuntime()
                    if beyondBuffer(price: info.doublePrice, target: rule.price, direction: direction, buffer: buffer) {
                        runtime.triggered = false; runtime.lastAlertAt = nil
                    }
                    let breached = direction == .up ? info.doublePrice >= rule.price : info.doublePrice <= rule.price
                    let fresh = breached && !runtime.triggered
                    var notify = false
                    if breached {
                        switch rule.repeatPolicy {
                        case .once: notify = !runtime.hasFired
                        case .everyCrossing: notify = fresh
                        case let .continuous(interval):
                            notify = fresh || (runtime.lastAlertAt.map { now.timeIntervalSince($0) >= interval } ?? false)
                        }
                    }
                    if notify {
                        if fresh { newlyBreached.append(rule) }
                        runtime.triggered = true; runtime.hasFired = true; runtime.lastAlertAt = now
                        let slot = rule.legacySlot.map { "第 \($0 + 1) 档" } ?? ""
                        route(AlertEvent(kind: .breach, identity: rule.id,
                            title: "⚠️ 预警: \(instrument.displayName) \(direction.verb)",
                            body: "【\(instrument.displayName)】已\(direction.verb)\(slot)目标价！\n当前价: \(info.doublePrice)\n目标价: \(rule.price)"),
                            state: &next, now: now, events: &events)
                    }
                    next.rules[rule.id] = runtime
                    if notify && fresh && rule.trailingBehavior == .perRule, let step = rule.trailingStep {
                        shift(rule, to: rule.price + (direction == .up ? step : -step), state: &next, now: now, events: &events)
                    }
                }
                let ladder = newlyBreached.filter { $0.trailingBehavior == .legacyLadder }.sorted {
                    if $0.price == $1.price { return ($0.legacySlot ?? 0) < ($1.legacySlot ?? 0) }
                    return direction == .up ? $0.price > $1.price : $0.price < $1.price
                }
                if ladder.count >= 2, let step = ladder[1].trailingStep {
                    shift(ladder[1], to: ladder[0].price + (direction == .up ? step : -step), state: &next, now: now, events: &events)
                }
            }
        }
        return (events, next)
    }
    public static func beyondBuffer(price: Double, target: Double, direction: AlertDirection, buffer: Double) -> Bool {
        let boundary = target * (direction == .up ? 1 - buffer : 1 + buffer)
        let tolerance = max(price.ulp, boundary.ulp) * 4
        return direction == .up ? price < boundary - tolerance : price > boundary + tolerance
    }
    private static func shift(_ rule: AlertRule, to target: Double, state: inout AlertState, now: Date, events: inout [AlertEvent]) {
        guard target.isFinite, target > 0 else { return }
        state.targetUpdates[rule.id] = target
        var runtime = state.rules[rule.id] ?? RuleRuntime()
        runtime.triggered = false; runtime.lastAlertAt = nil
        state.rules[rule.id] = runtime
        let slot = rule.legacySlot.map { "第 \($0 + 1) 档" } ?? "预警目标"
        route(AlertEvent(kind: .targetShift, identity: "tracking_\(rule.id)", title: "自动追踪目标已调整",
            body: "\(rule.instrument.displayName) \(rule.direction.displayName)\(slot)已从 \(rule.price) 自动顺延到 \(target)",
            oldTarget: rule.price, newTarget: target), state: &state, now: now, events: &events)
    }
    public static func evaluateMessage(_ event: AlertEvent, state: AlertState, now: Date)
        -> (events: [AlertEvent], newState: AlertState) {
        var next = state; next.targetUpdates.removeAll()
        var events: [AlertEvent] = []
        flushPending(state: &next, now: now, events: &events)
        route(event, state: &next, now: now, events: &events)
        return (events, next)
    }
    private static func route(_ event: AlertEvent, state: inout AlertState, now: Date, events: inout [AlertEvent]) {
        var event = event
        if state.quietHours.contains(now) {
            event.delivery = .recordOnly
            state.pending[event.identity] = PendingNotice(title: event.title, body: event.body,
                count: (state.pending[event.identity]?.count ?? 0) + 1, lastRecordedAt: now)
        }
        events.append(event)
    }
    private static func flushPending(state: inout AlertState, now: Date, events: inout [AlertEvent]) {
        guard !state.quietHours.contains(now), !state.pending.isEmpty else { return }
        let records = state.pending.sorted {
            if $0.value.lastRecordedAt == $1.value.lastRecordedAt { return $0.key < $1.key }
            return $0.value.lastRecordedAt < $1.value.lastRecordedAt
        }.map { $0.value }
        let count = records.reduce(0) { $0 + $1.count }
        let details = records.prefix(12).map { "\($0.body)（记录 \($0.count) 次）" }.joined(separator: "\n")
        let extra = records.count > 12 ? "\n其余记录请查看系统日志。" : ""
        events.append(AlertEvent(kind: .quietSummary, identity: "quiet_summary", title: "免打扰结束：金价提醒汇总",
            body: "免打扰期间共记录 \(count) 次提醒：\n" + details + extra))
        state.pending.removeAll()
    }
}
