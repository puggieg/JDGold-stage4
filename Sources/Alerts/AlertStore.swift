import Foundation

public enum AlertStoreError: Error, CustomStringConvertible {
    case invalidRules, corruptJSON, missingMigratedJSON, unsupportedVersion(Int)
    public var description: String {
        switch self {
        case .invalidRules: return "规则数值、ID 或档位无效"
        case .corruptJSON: return "规则 JSON 无法读取，原数据已保留，未用旧键覆盖"
        case .missingMigratedJSON: return "迁移后规则 JSON 缺失，停止重复迁移以免恢复已删除的规则"
        case let .unsupportedVersion(version): return "不支持规则版本 \(version)，原数据已保留"
        }
    }
}
public struct EditedInstrument {
    public var instrument: Instrument
    public var upPrices: [Double]
    public var downPrices: [Double]
    public init(instrument: Instrument, upPrices: [Double], downPrices: [Double]) {
        self.instrument = instrument; self.upPrices = upPrices; self.downPrices = downPrices
    }
}
// 存储只处理持久化与迁移；是否触发由纯 AlertEngine 判断。
public final class AlertStore {
    public static let rulesKey = "alertRulesJSON"
    public static let migrationKey = "alertRulesMigrationCompleted_v1"
    private struct Archive: Codable { var version: Int; var rules: [AlertRule] }
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public private(set) var rules: [AlertRule] = []
    public init(defaults: UserDefaults) throws {
        self.defaults = defaults
        if let raw = defaults.object(forKey: Self.rulesKey) {
            guard let data = raw as? Data else { throw AlertStoreError.corruptJSON }
            do {
                let archive = try decoder.decode(Archive.self, from: data)
                guard archive.version == 1 else { throw AlertStoreError.unsupportedVersion(archive.version) }
                try Self.validate(archive.rules)
                rules = archive.rules
                defaults.set(true, forKey: Self.migrationKey)
            } catch let error as AlertStoreError { throw error }
            catch { throw AlertStoreError.corruptJSON }
        } else {
            guard !defaults.bool(forKey: Self.migrationKey) else { throw AlertStoreError.missingMigratedJSON }
            try save(Self.migrateLegacy(defaults: defaults))
            // JSON 先写入并读回验证，再标记迁移；原五十键不删除。
            guard let written = defaults.data(forKey: Self.rulesKey),
                  let restored = try? decoder.decode(Archive.self, from: written),
                  restored.version == 1, restored.rules == rules else { throw AlertStoreError.corruptJSON }
            defaults.set(true, forKey: Self.migrationKey)
        }
    }
    public static func legacyID(_ instrument: Instrument, _ direction: AlertDirection, _ slot: Int) -> String {
        "legacy_\(direction.rawValue)_\(instrument.rawValue)_\(slot)"
    }
    public static func migrateLegacy(defaults: UserDefaults) -> [AlertRule] {
        var result: [AlertRule] = []
        let interval = defaults.double(forKey: "alertRepeatInterval")
        let policy: RepeatPolicy = interval.isFinite && interval > 0 ? .continuous(interval: interval) : .everyCrossing
        for instrument in Instrument.alertInstruments {
            let step = defaults.double(forKey: instrument.legacyStepKey)
            for direction in AlertDirection.allCases {
                for slot in 0..<Instrument.slotsPerDirection {
                    let value = defaults.double(forKey: "target_\(direction.rawValue)_\(instrument.rawValue)_\(slot)")
                    guard value.isFinite, value > 0 else { continue }
                    result.append(AlertRule(id: legacyID(instrument, direction, slot), instrument: instrument,
                        direction: direction, price: value, repeatPolicy: policy,
                        trailingStep: step.isFinite && step > 0 ? step : nil,
                        legacySlot: slot, trailingBehavior: .legacyLadder))
                }
            }
        }
        return result
    }
    public static func validate(_ rules: [AlertRule]) throws {
        guard rules.allSatisfy({ $0.isValid }), Set(rules.map { $0.id }).count == rules.count else { throw AlertStoreError.invalidRules }
        let slots = rules.compactMap { rule -> String? in
            guard let slot = rule.legacySlot else { return nil }
            return "\(rule.instrument.rawValue)_\(rule.direction.rawValue)_\(slot)"
        }
        guard slots.count == Set(slots).count else { throw AlertStoreError.invalidRules }
    }
    public func save(_ newRules: [AlertRule]) throws {
        try Self.validate(newRules)
        let data = try encoder.encode(Archive(version: 1, rules: newRules))
        defaults.set(data, forKey: Self.rulesKey)
        rules = newRules
    }
    public func rule(for instrument: Instrument, direction: AlertDirection, slot: Int) -> AlertRule? {
        rules.first { $0.instrument == instrument && $0.direction == direction && $0.legacySlot == slot }
    }
    public func price(for instrument: Instrument, direction: AlertDirection, slot: Int) -> Double {
        rule(for: instrument, direction: direction, slot: slot)?.price ?? 0
    }
    public func applyTargetUpdates(_ updates: [String: Double]) throws {
        guard !updates.isEmpty else { return }
        var changed = rules
        for index in changed.indices { if let value = updates[changed[index].id] { changed[index].price = value } }
        try save(changed)
    }
    // 原有编辑弹窗整组提交，保留已有规则的 ID、note 和提醒策略。
    public func updateEditor(sections: [EditedInstrument], steps: [Instrument.Group: Double]) throws {
        var changed = rules
        let interval = defaults.double(forKey: "alertRepeatInterval")
        let policy: RepeatPolicy = interval.isFinite && interval > 0 ? .continuous(interval: interval) : .everyCrossing
        for section in sections {
            guard section.upPrices.count == Instrument.slotsPerDirection, section.downPrices.count == Instrument.slotsPerDirection else { throw AlertStoreError.invalidRules }
            for (direction, prices) in [(AlertDirection.up, section.upPrices), (.down, section.downPrices)] {
                for (slot, value) in prices.enumerated() {
                    guard value.isFinite, value >= 0 else { throw AlertStoreError.invalidRules }
                    let existing = changed.firstIndex { $0.instrument == section.instrument && $0.direction == direction && $0.legacySlot == slot }
                    if value == 0 { if let index = existing { changed.remove(at: index) } }
                    else if let index = existing { changed[index].price = value }
                    else {
                        changed.append(AlertRule(id: Self.legacyID(section.instrument, direction, slot), instrument: section.instrument,
                            direction: direction, price: value, repeatPolicy: policy, legacySlot: slot, trailingBehavior: .legacyLadder))
                    }
                }
            }
        }
        for index in changed.indices {
            if let step = steps[changed[index].instrument.group] {
                guard step.isFinite, step >= 0 else { throw AlertStoreError.invalidRules }
                changed[index].trailingStep = step > 0 ? step : nil
            }
        }
        try save(changed)
        for (group, step) in steps { defaults.set(step, forKey: group == .domestic ? "autoStep_domestic" : "autoStep_international") }
    }
    public func loadPending() throws -> [String: PendingNotice] {
        guard let data = defaults.data(forKey: "pendingQuietNotifications") else { return [:] }
        return try decoder.decode([String: PendingNotice].self, from: data)
    }
    public func savePending(_ pending: [String: PendingNotice]) throws {
        defaults.set(try encoder.encode(pending), forKey: "pendingQuietNotifications")
    }
    // 新“仅一次”规则的消费状态持久化；迁移的每次穿越规则仍保留原启动语义。
    public func consumedOnceRules() -> Set<String> {
        let saved = Set(defaults.stringArray(forKey: "consumedOnceAlertRuleIDs") ?? [])
        return saved.intersection(Set(rules.filter { $0.repeatPolicy == .once }.map { $0.id }))
    }
    public func saveOnceState(_ state: AlertState) {
        let ids = rules.filter { $0.repeatPolicy == .once && state.rules[$0.id]?.hasFired == true }.map { $0.id }.sorted()
        defaults.set(ids, forKey: "consumedOnceAlertRuleIDs")
    }
}
