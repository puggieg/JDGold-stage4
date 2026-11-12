import Foundation

// 新高/新低的冷静期状态独立于原有预警规则存储；损坏时从空状态开始，不影响旧规则。
public final class ExtremeAlertStore {
    public static let stateKey = "extremeAlertStateJSON"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public func load() -> ExtremeAlertState {
        guard let data = defaults.data(forKey: Self.stateKey),
              let value = try? decoder.decode(ExtremeAlertState.self, from: data) else { return ExtremeAlertState() }
        return value
    }
    public func save(_ state: ExtremeAlertState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }
}
