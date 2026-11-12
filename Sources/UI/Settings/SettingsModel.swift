#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa
import SwiftUI

@MainActor final class SettingsModel: ObservableObject {
    let defaults: UserDefaults
    let alertStore: AlertStore?
    @Published var prices = GoldPrices()
    @Published var now = Date()
    @Published private(set) var rules: [AlertRule] = []
    @Published var consumedOnce = Set<String>()
    @Published var selectedTab = 0
    @Published var errorMessage = ""
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval"); onIntervalChange?() } }
    @Published var statusInstrument: Instrument { didSet { defaults.set(statusInstrument.rawValue, forKey: "statusBarPriceKey"); onAppearanceChange?(); onMenuBankChange?() } }
    @Published var colorMovement: Bool { didSet { defaults.set(colorMovement, forKey: "statusBarColorMovement"); onAppearanceChange?() } }
    @Published var showMovement: Bool { didSet { defaults.set(showMovement, forKey: "statusBarShowMovement"); onAppearanceChange?() } }
    @Published var floatingVisible: Bool { didSet { defaults.set(floatingVisible, forKey: "floatingVisible"); onAppearanceChange?() } }
    @Published var floatingMini: Bool { didSet { defaults.set(floatingMini, forKey: "floatingMini"); onAppearanceChange?() } }
    @Published var floatingInstrument: Instrument { didSet { defaults.set(floatingInstrument.rawValue, forKey: "floatingInstrument"); onAppearanceChange?() } }
    @Published var floatingOpacity: Double { didSet { defaults.set(floatingOpacity, forKey: "floatingOpacity"); onAppearanceChange?() } }
    @Published var floatingPinned: Bool { didSet { defaults.set(floatingPinned, forKey: "floatingPinned"); onAppearanceChange?() } }
    @Published var mousePassthrough: Bool { didSet { defaults.set(mousePassthrough, forKey: "floatingMousePassthrough"); onAppearanceChange?() } }
    // 阶段五：菜单栏其余两家银行的常显示开关，以及今日新高/新低提醒配置。
    @Published var alwaysShowAllBanks: Bool { didSet { defaults.set(alwaysShowAllBanks, forKey: "alwaysShowAllBanks"); onAppearanceChange?() } }
    @Published var extremeHighEnabled: Bool { didSet { defaults.set(extremeHighEnabled, forKey: "extremeHighEnabled"); onExtremeConfigChange?() } }
    @Published var extremeLowEnabled: Bool { didSet { defaults.set(extremeLowEnabled, forKey: "extremeLowEnabled"); onExtremeConfigChange?() } }
    @Published var extremeInstruments: Set<Instrument> { didSet { defaults.set(extremeInstruments.map { $0.rawValue }.sorted(), forKey: "extremeAlertInstruments"); onExtremeConfigChange?() } }
    @Published var extremeCooldownMinutes: Double { didSet { defaults.set(extremeCooldownMinutes, forKey: "extremeCooldownMinutes"); onExtremeConfigChange?() } }
    @Published var extremeThresholdPercent: Double { didSet { defaults.set(extremeThresholdPercent, forKey: "extremeThresholdPercent"); onExtremeConfigChange?() } }
    @Published var systemNotifications: Bool { didSet { defaults.set(systemNotifications, forKey: "systemNotifications"); onNotificationChange?() } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "notificationSound"); onNotificationChange?() } }
    @Published var quietEnabled: Bool { didSet { defaults.set(quietEnabled, forKey: "quietHoursEnabled") } }
    @Published var quietStart: Int { didSet { defaults.set(quietStart, forKey: "quietHoursStartMinute") } }
    @Published var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: "quietHoursEndMinute") } }
    @Published var notificationStatus = "正在读取授权状态…"
    @Published var loginEnabled = false
    @Published var loginStatus = ""
    @Published var barkInput = ""
    @Published var barkStatus = "尚未绑定"
    @Published var barkBusy = true
    @Published var barkResult = ""
    var onIntervalChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    // 「显示品种」变化时重建菜单，让国内组默认只显示的那家银行跟着变。
    var onMenuBankChange: (() -> Void)?
    var onExtremeConfigChange: (() -> Void)?
    var onNotificationChange: (() -> Void)?
    var onRulesChanged: ((Set<String>) -> Void)?
    var onSaveBark: ((BarkLink?) async throws -> Void)?
    var onTestBark: (() async -> String)?
    var onRequestNotification: (() -> Void)?
    var onLoginChange: ((Bool) -> Void)?
    var onCheckUpdate: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["refreshInterval": 10.0, "alertRearmBufferRatio": 0.001, "alertRepeatInterval": 0.0,
            "quietHoursEnabled": true, "quietHoursStartMinute": 1380, "quietHoursEndMinute": 480,
            "statusBarColorMovement": true, "statusBarShowMovement": true, "floatingOpacity": 0.92,
            "systemNotifications": true, "notificationSound": true,
            "alwaysShowAllBanks": false, "extremeHighEnabled": false, "extremeLowEnabled": false,
            "extremeAlertInstruments": ["icbc"], "extremeCooldownMinutes": 5.0, "extremeThresholdPercent": 0.1])
        do { alertStore = try AlertStore(defaults: defaults) }
        catch { alertStore = nil; appLog("规则存储", String(describing: error)) }
        refreshInterval = [3.0,5,10,30,60].contains(defaults.double(forKey: "refreshInterval")) ? defaults.double(forKey: "refreshInterval") : 10
        let selected = Instrument(rawValue: defaults.string(forKey: "statusBarPriceKey") ?? "") ?? .minsheng
        statusInstrument = selected
        colorMovement = defaults.bool(forKey: "statusBarColorMovement"); showMovement = defaults.bool(forKey: "statusBarShowMovement")
        floatingVisible = defaults.bool(forKey: "floatingVisible"); floatingMini = defaults.bool(forKey: "floatingMini")
        floatingInstrument = Instrument(rawValue: defaults.string(forKey: "floatingInstrument") ?? "") ?? selected
        let opacity = defaults.double(forKey: "floatingOpacity")
        floatingOpacity = opacity.isFinite ? min(1, max(0.5, opacity)) : 0.92
        floatingPinned = defaults.bool(forKey: "floatingPinned"); mousePassthrough = defaults.bool(forKey: "floatingMousePassthrough")
        alwaysShowAllBanks = defaults.bool(forKey: "alwaysShowAllBanks")
        extremeHighEnabled = defaults.bool(forKey: "extremeHighEnabled"); extremeLowEnabled = defaults.bool(forKey: "extremeLowEnabled")
        extremeInstruments = Set((defaults.stringArray(forKey: "extremeAlertInstruments") ?? ["icbc"]).compactMap { Instrument(rawValue: $0) })
        let cooldown = defaults.double(forKey: "extremeCooldownMinutes")
        extremeCooldownMinutes = [3.0,5,10,15].contains(cooldown) ? cooldown : 5
        let threshold = defaults.double(forKey: "extremeThresholdPercent")
        extremeThresholdPercent = [0.05,0.1,0.3,0.5].contains(threshold) ? threshold : 0.1
        systemNotifications = defaults.bool(forKey: "systemNotifications"); soundEnabled = defaults.bool(forKey: "notificationSound")
        quietEnabled = defaults.bool(forKey: "quietHoursEnabled")
        let start = defaults.integer(forKey: "quietHoursStartMinute"), end = defaults.integer(forKey: "quietHoursEndMinute")
        quietStart = (0..<1440).contains(start) ? start : 1380; quietEnd = (0..<1440).contains(end) ? end : 480
        rules = alertStore?.rules ?? []; consumedOnce = alertStore?.consumedOnceRules() ?? []
        if alertStore == nil { errorMessage = "规则读取失败，原数据已保留。请先备份偏好，不要重置。" }
    }
    var activeRuleCount: Int { rules.filter { $0.enabled && !($0.repeatPolicy == .once && consumedOnce.contains($0.id)) }.count }
    var extremeAlertConfig: ExtremeAlertConfig {
        ExtremeAlertConfig(highEnabled: extremeHighEnabled, lowEnabled: extremeLowEnabled,
                           instruments: extremeInstruments, cooldown: extremeCooldownMinutes * 60,
                           thresholdRatio: extremeThresholdPercent / 100)
    }
    func toggleExtremeInstrument(_ instrument: Instrument) {
        var selected = extremeInstruments
        if selected.contains(instrument) { selected.remove(instrument) } else { selected.insert(instrument) }
        extremeInstruments = selected
    }
    func refreshRules() { rules = alertStore?.rules ?? []; consumedOnce = alertStore?.consumedOnceRules() ?? [] }
    private func commit(_ changed: [AlertRule], reset: Set<String>) -> Bool {
        guard let store = alertStore else { return false }
        do { try store.save(changed); rules = store.rules; onRulesChanged?(reset); errorMessage = ""; return true }
        catch { errorMessage = "未保存：\(error)"; appLog("规则存储", String(describing: error)); return false }
    }
    @discardableResult func save(_ rule: AlertRule) -> Bool {
        var changed = rules
        if let index = changed.firstIndex(where: { $0.id == rule.id }) { changed[index] = rule } else { changed.append(rule) }
        return commit(changed, reset: [rule.id])
    }
    func toggle(_ rule: AlertRule, enabled: Bool) { var changed = rule; changed.enabled = enabled; _ = save(changed) }
    func remove(_ rule: AlertRule) { _ = commit(rules.filter { $0.id != rule.id }, reset: [rule.id]) }
    func disableAll() {
        let changed = rules.map { rule -> AlertRule in var value = rule; value.enabled = false; return value }
        _ = commit(changed, reset: Set(rules.map { $0.id }))
    }
    func saveBark(unbind: Bool = false) {
        guard !barkBusy, let handler = onSaveBark else { return }
        let parsed: BarkLink?
        do { parsed = unbind ? nil : try BarkLinkParser.parse(barkInput) }
        catch { barkResult = String(describing: error); return }
        barkBusy = true
        Task { @MainActor in
            do {
                try await handler(parsed)
                barkStatus = parsed.map { "已绑定 \($0.maskedKey)" } ?? "尚未绑定"
                barkInput = ""; barkResult = unbind ? "已解绑。" : "已保存到钥匙串。可发送测试验证手机是否收到。"
            } catch { barkResult = "保存失败，原绑定已保留。"; appLog("Bark", "钥匙串写入失败") }
            barkBusy = false
        }
    }
    func testBark() {
        guard !barkBusy, let handler = onTestBark else { return }
        barkBusy = true; barkResult = "正在发送…"
        Task { @MainActor in barkResult = await handler(); barkBusy = false }
    }
}
