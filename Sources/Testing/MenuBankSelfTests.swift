import Foundation

// 菜单栏默认银行跟随「显示品种」的纯函数断言。
public enum MenuBankSelfTests {
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "菜单默认银行跟随显示品种", run: run)]
    }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestFailure(description: message) }
    }
    private static func run() throws {
        for bank in Instrument.allCases.filter({ $0.group == .domestic }) {
            try check(MenuBankPresentation.primary(bank) == bank, "选中 \(bank.displayName) 就默认显示它")
            let order = MenuBankPresentation.domesticOrder(primary: bank)
            try check(order.count == 3 && Set(order).count == 3 && order.first == bank, "三家齐全、无重复、默认银行排第一")
            try check(Set(MenuBankPresentation.otherBanks(primary: bank)) == Set(order.dropFirst()), "其余两家是另外两家")
            try check(MenuBankPresentation.otherBanks(primary: bank).count == 2, "始终是其余两个")
        }
        // 状态栏显示国际品种或美元指数时，国内组没有对应银行，回退到工商银行。
        for other in Instrument.allCases.filter({ $0.group != .domestic }) {
            try check(MenuBankPresentation.primary(other) == .icbc, "\(other.displayName) 回退工商银行")
        }
        try check(MenuBankPresentation.domesticOrder(primary: .minsheng) == [.minsheng, .icbc, .zheshang], "民生为默认时其余顺序不变")
        try check(MenuBankPresentation.domesticOrder(primary: .icbc) == [.icbc, .minsheng, .zheshang], "工行为默认时保持旧顺序")
    }
}
