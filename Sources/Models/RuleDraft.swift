import Foundation

public enum ReminderKind: String, CaseIterable { case once = "仅一次", crossing = "每次穿越", continuous = "持续提醒" }
public struct RuleDraft: Identifiable {
    public var id: String
    public var instrument: Instrument
    public var direction: AlertDirection
    public var targetText: String
    public var reminder: ReminderKind
    public var intervalMinutes: String
    public var stepText: String
    public var enabled: Bool
    public var note: String
    public let original: AlertRule?
    public init(rule: AlertRule? = nil, instrument: Instrument = .minsheng) {
        original = rule; id = rule?.id ?? UUID().uuidString
        self.instrument = rule?.instrument ?? instrument
        direction = rule?.direction ?? .up; targetText = rule.map { String(format: "%.2f", $0.price) } ?? ""
        reminder = .crossing; intervalMinutes = "30"
        if let rule = rule {
            switch rule.repeatPolicy {
            case .once: reminder = .once
            case .everyCrossing: reminder = .crossing
            case .continuous(let seconds): reminder = .continuous; intervalMinutes = String(format: "%g", seconds / 60)
            }
        }
        stepText = rule?.trailingStep.map { String(format: "%g", $0) } ?? ""
        enabled = rule?.enabled ?? true; note = rule?.note ?? ""
    }
    public var target: Double? { guard let value = parsePriceInput(targetText), value > 0 else { return nil }; return value }
    public var validationMessage: String? {
        guard target != nil else { return "目标价须为大于 0 的数字，支持中文逗号和全角数字。" }
        guard let step = parsePriceInput(stepText), step >= 0 else { return "自动顺延步长无法解析。" }
        if reminder == .continuous {
            guard let minutes = parsePriceInput(intervalMinutes), minutes > 0, (minutes * 60).isFinite else { return "提醒间隔须大于 0 分钟。" }
        }
        return nil
    }
    public func triggersImmediately(_ info: PriceInfo) -> Bool {
        guard info.isValid, let value = target else { return false }
        return direction == .up ? value <= info.doublePrice : value >= info.doublePrice
    }
    public mutating func fillShortcut(percent: Double, current: PriceInfo) {
        guard current.isValid else { return }
        direction = percent > 0 ? .up : .down
        targetText = String(format: "%.2f", current.doublePrice * (1 + percent / 100))
    }
    public func makeRule() -> AlertRule? {
        guard validationMessage == nil, let price = target, let step = parsePriceInput(stepText) else { return nil }
        let policy: RepeatPolicy
        switch reminder {
        case .once: policy = .once
        case .crossing: policy = .everyCrossing
        case .continuous: guard let minutes = parsePriceInput(intervalMinutes) else { return nil }; policy = .continuous(interval: minutes * 60)
        }
        // 沿用原 ID 和旧档位追踪语义；改变品种/方向后成为独立新规则。
        let sameGroup = original?.instrument == instrument && original?.direction == direction
        return AlertRule(id: id, instrument: instrument, direction: direction, price: price, repeatPolicy: policy,
                         trailingStep: step > 0 ? step : nil, enabled: enabled, note: note,
                         legacySlot: sameGroup ? original?.legacySlot : nil,
                         trailingBehavior: sameGroup ? (original?.trailingBehavior ?? .perRule) : .perRule)
    }
}
