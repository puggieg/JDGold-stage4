import Foundation

// 仅持久化和旧键迁移使用 rawValue；业务统一使用枚举，避免拼错品种字符串。
public enum Instrument: String, Codable, CaseIterable, Sendable {
    case minsheng, icbc, zheshang, london, newyork, usdIndex
    public enum Group: String, Codable, Sendable { case domestic, international, index }
    public var displayName: String {
        switch self {
        case .minsheng: return "民生银行"
        case .icbc: return "工商银行"
        case .zheshang: return "浙商银行"
        case .london: return "伦敦金"
        case .newyork: return "纽约金"
        case .usdIndex: return "美元指数"
        }
    }
    public var group: Group {
        switch self {
        case .minsheng, .icbc, .zheshang: return .domestic
        case .london, .newyork: return .international
        case .usdIndex: return .index
        }
    }
    public var unit: String { group == .domestic ? "元/克" : (group == .international ? "$/oz" : "") }
    public var precision: Int { 2 }
    public var legacyStepKey: String { group == .domestic ? "autoStep_domestic" : "autoStep_international" }
    public static let alertInstruments: [Instrument] = [.minsheng, .icbc, .zheshang, .london, .newyork]
    public static let slotsPerDirection = 5
}
