#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

@MainActor enum DisplayFormatters {
    // 界面只在主线程使用同一个格式器；来源时间统一标北京时间。
    private static let sourceTime: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai"); value.dateFormat = "MM-dd HH:mm:ss"
        return value
    }()
    static func sourceText(_ date: Date) -> String { sourceTime.string(from: date) }
}
@MainActor extension PriceInfo {
    func movementColor(now: Date = Date()) -> NSColor {
        guard !MarketPresentation.isDelayed(self, now: now), let change = numericChangeRate, change != 0 else { return .secondaryLabelColor }
        return change > 0 ? .systemRed : .systemGreen
    }
    func sourceDescription(now: Date = Date()) -> String {
        let source = sourceUpdatedAt.map { "来源 \(DisplayFormatters.sourceText($0)) 北京时间" } ?? "来源时间未提供"
        let state = isStale ? " · 延迟" : (MarketPresentation.isDelayed(self, now: now) ? " · 休市/延迟" : "")
        return source + state
    }
}
