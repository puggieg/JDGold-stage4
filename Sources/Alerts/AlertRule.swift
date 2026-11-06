import Foundation

public enum AlertDirection: String, Codable, CaseIterable, Sendable {
    case up, down
    public var isUpward: Bool { self == .up }
    public var displayName: String { isUpward ? "涨破" : "跌破" }
    public var verb: String { isUpward ? "📈突破" : "📉跌破" }
}
public enum RepeatPolicy: Codable, Equatable, Sendable {
    case once
    case everyCrossing
    case continuous(interval: TimeInterval)
}
public enum TrailingBehavior: String, Codable, Sendable {
    case perRule
    // 兼容阶段一：同轮突破多个档位时，顺延次极端档位，保留老用户行为。
    case legacyLadder
}
public struct AlertRule: Codable, Equatable, Sendable {
    public var id: String
    public var instrument: Instrument
    public var direction: AlertDirection
    public var price: Double
    public var repeatPolicy: RepeatPolicy
    public var trailingStep: Double?
    public var enabled: Bool
    public var note: String
    // 兼容元数据：保留旧编辑面板的空档位置，不新增用户可见控件。
    public var legacySlot: Int?
    public var trailingBehavior: TrailingBehavior
    public init(id: String = UUID().uuidString, instrument: Instrument, direction: AlertDirection, price: Double,
                repeatPolicy: RepeatPolicy = .everyCrossing, trailingStep: Double? = nil, enabled: Bool = true,
                note: String = "", legacySlot: Int? = nil, trailingBehavior: TrailingBehavior = .perRule) {
        self.id = id; self.instrument = instrument; self.direction = direction; self.price = price
        self.repeatPolicy = repeatPolicy; self.trailingStep = trailingStep; self.enabled = enabled; self.note = note
        self.legacySlot = legacySlot; self.trailingBehavior = trailingBehavior
    }
    private enum CodingKeys: String, CodingKey {
        case id, instrument, direction, price, repeatPolicy, trailingStep, enabled, note, legacySlot, trailingBehavior
    }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        instrument = try fields.decode(Instrument.self, forKey: .instrument)
        direction = try fields.decode(AlertDirection.self, forKey: .direction)
        price = try fields.decode(Double.self, forKey: .price)
        repeatPolicy = try fields.decode(RepeatPolicy.self, forKey: .repeatPolicy)
        trailingStep = try fields.decodeIfPresent(Double.self, forKey: .trailingStep)
        enabled = try fields.decode(Bool.self, forKey: .enabled)
        note = try fields.decode(String.self, forKey: .note)
        legacySlot = try fields.decodeIfPresent(Int.self, forKey: .legacySlot)
        trailingBehavior = try fields.decodeIfPresent(TrailingBehavior.self, forKey: .trailingBehavior) ?? .perRule
    }
    public var isValid: Bool {
        guard !id.isEmpty, price.isFinite, price > 0 else { return false }
        if let step = trailingStep, !step.isFinite || step <= 0 { return false }
        if case let .continuous(interval) = repeatPolicy, !interval.isFinite || interval <= 0 { return false }
        if let slot = legacySlot, !(0..<Instrument.slotsPerDirection).contains(slot) { return false }
        return true
    }
}
