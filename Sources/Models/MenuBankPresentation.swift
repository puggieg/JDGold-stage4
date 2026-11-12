import Foundation

// 菜单栏「国内积存金」默认显示哪一家：跟随偏好里的「显示品种」。
// 选中非国内银行品种时回退到工商银行；纯函数，便于固定输入验证。
public enum MenuBankPresentation {
    public static func primary(_ statusInstrument: Instrument) -> Instrument {
        statusInstrument.group == .domestic ? statusInstrument : .icbc
    }
    // 默认银行排第一，另外两家保持原有固定顺序跟在后面。
    public static func domesticOrder(primary: Instrument) -> [Instrument] {
        [primary] + Instrument.allCases.filter { $0.group == .domestic && $0 != primary }
    }
    public static func otherBanks(primary: Instrument) -> [Instrument] {
        Array(domesticOrder(primary: primary).dropFirst())
    }
}
