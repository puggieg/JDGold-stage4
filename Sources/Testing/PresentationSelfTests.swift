import Foundation

// 阶段三新增可独立验证的展示与交互规则，不需要创建窗口。
public enum PresentationSelfTests {
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "来源时间与非法日期", run: timestamps),
         SelfTestCase(name: "延迟边界与并列最低", run: quotes),
         SelfTestCase(name: "规则快捷填入与校验", run: drafts),
         SelfTestCase(name: "Bark 链接参数与路径安全", run: bark),
         SelfTestCase(name: "负坐标与断开显示器", run: screens)]
    }
    private static func check(_ result: Bool, _ message: String) throws {
        if !result { throw SelfTestFailure(description: message) }
    }
    private static func timestamps() throws {
        let date = SourceTimestamp.milliseconds("1791988717000")!
        try check(abs(date.timeIntervalSince1970 * 1000 - 1791988717000) < 0.01, "毫秒往返")
        try check(SourceTimestamp.sina(date: "2026-10-14", time: "22:38:37") == date, "北京时间字段")
        try check(SourceTimestamp.sina(date: "2026-02-30", time: "12:00:00") == nil, "拒绝滚动到三月")
        try check(SourceTimestamp.sina(date: "2026-10-14", time: "24:00:00") == nil, "非法小时")
        for raw in ["nan", "inf", "0", "-1", "abc"] { try check(SourceTimestamp.milliseconds(raw) == nil, "拒绝无效时间戳") }
        let bankData = Data("{\"resultData\":{\"datas\":{\"price\":\"885.04\",\"time\":\"1791988717000\"}}}".utf8)
        let bank = try MinshengProvider().parse(bankData).prices[.minsheng]
        try check(bank?.sourceUpdatedAt == date, "银行毫秒字符串解析")
        let fixture = "var hq_str_hf_GC=\"4119.908,,4121.200,4121.500,4193.500,4101.600,22:38:32,4177.300,4184.200,0,3,1,2026-10-14,纽约黄金,0\";"
        let info = parseSinaLine(fixture)
        try check(info.yesterdayPrice == "4177.30" && info.sourceUpdatedAt == SourceTimestamp.sina(date: "2026-10-14", time: "22:38:32"), "新浪昨收和时间")
    }
    private static func quotes() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var info = PriceInfo(price: "100", changeRate: "0.00%")
        info.sourceUpdatedAt = now.addingTimeInterval(-299)
        try check(!MarketPresentation.isDelayed(info, now: now), "未到边界")
        info.sourceUpdatedAt = now.addingTimeInterval(-300)
        try check(MarketPresentation.isDelayed(info, now: now), "五分钟边界")
        info.sourceUpdatedAt = nil; info.lastPriceChangeAt = now.addingTimeInterval(-300)
        try check(MarketPresentation.isDelayed(info, now: now), "未知时间但未变价")
        info.lastPriceChangeAt = nil
        try check(MarketPresentation.movement(info) == "— 0.00%", "平盘")
        info.changeRate = "-0.42%"; try check(MarketPresentation.movement(info) == "▼0.42%", "下跌绝对值")
        info.changeRate = "+0.42%"; try check(MarketPresentation.movement(info) == "▲0.42%", "上涨")
        var prices = GoldPrices(values: [.minsheng: info, .icbc: info, .zheshang: PriceInfo(price: "101")])
        try check(MarketPresentation.lowestBanks(prices, now: now) == [.minsheng,.icbc], "并列最低")
        prices.values[.zheshang]?.isStale = true
        try check(MarketPresentation.lowestBanks(prices, now: now).isEmpty, "陈旧报价不参与比较")
        try check(MarketPresentation.distance(target: 102, info: info) == "距现价 +2.00%", "距离计算")
    }
    private static func drafts() throws {
        let current = PriceInfo(price: "1000")
        var draft = RuleDraft()
        for percent in [-2.0,-1,1,2] {
            draft.fillShortcut(percent: percent, current: current)
            try check(draft.target == 1000 * (1 + percent / 100), "快捷填入价格")
            try check(draft.direction == (percent > 0 ? .up : .down), "快捷填入方向")
        }
        draft.targetText = "９９９，５"; draft.direction = .up
        try check(draft.triggersImmediately(current), "立即触发")
        draft.targetText = "abc"; try check(draft.makeRule() == nil, "不能静默保存为零")
        draft.targetText = "1001"; draft.stepText = "bad"; try check(draft.makeRule() == nil, "非法步长")
        draft.stepText = ""; draft.reminder = .continuous; draft.intervalMinutes = "0"
        try check(draft.makeRule() == nil, "非法间隔")
        draft.intervalMinutes = "０，５"; try check(draft.makeRule()?.repeatPolicy == .continuous(interval: 30), "小数间隔")
        let old = AlertRule(id: "old", instrument: .icbc, direction: .down, price: 900, legacySlot: 2, trailingBehavior: .legacyLadder)
        var editing = RuleDraft(rule: old)
        try check(editing.makeRule()?.id == old.id && editing.makeRule()?.legacySlot == 2, "保留迁移档位")
        editing.instrument = .london
        try check(editing.makeRule()?.legacySlot == nil && editing.makeRule()?.trailingBehavior == .perRule, "改品种去除旧档位")
    }
    private static func bark() throws {
        let link = try BarkLinkParser.parse("https://api.day.app/Key_123/title/body?level=critical&call=1")
        try check(link.key == "Key_123" && link.level == "critical" && link.continuousRing, "解析通知参数")
        try check(link.maskedKey == "••••_123" && link.query == "level=critical&call=1", "隐藏 Key 保留参数")
        try check(try BarkLinkParser.parse("PlainKey").key == "PlainKey", "单独 Key")
        for invalid in ["https://evil.com/Key", "http://api.day.app/Key", "https://api.day.app/Key%2FSecret", "https://api.day.app/Key?call=0", "https://api.day.app/Key?level=bad", "https://api.day.app/Key?call=1&call=1", ""] {
            var rejected = false; do { _ = try BarkLinkParser.parse(invalid) } catch { rejected = true }
            try check(rejected, "应拒绝链接：\(invalid)")
        }
        // 所有推送统一归到 Gold Monitor 分组，且不能出现重复的 group 参数。
        try check(BarkLinkParser.notificationGroup == "Gold Monitor", "分组名称")
        try check(BarkLinkParser.groupedQuery(nil) == "group=Gold%20Monitor", "无参数时也归组")
        try check(BarkLinkParser.groupedQuery("") == "group=Gold%20Monitor", "空参数也归组")
        try check(BarkLinkParser.groupedQuery("level=critical&call=1") == "level=critical&call=1&group=Gold%20Monitor", "保留原参数")
        try check(BarkLinkParser.groupedQuery("group=Other&level=active&GROUP=Foo") == "level=active&group=Gold%20Monitor", "覆盖已有 group 且不重复")
        try check(URLComponents(string: "https://api.day.app/Key/x/y?\(BarkLinkParser.groupedQuery(nil))")?.queryItems?.first?.value == "Gold Monitor", "分组值可正确解码")
    }
    private static func screens() throws {
        let left = PanelScreen(id: "left", frame: PanelFrame(x: -1920, y: 0, width: 1920, height: 1080))
        let right = PanelScreen(id: "right", frame: PanelFrame(x: 0, y: 24, width: 1440, height: 876))
        let saved = PanelFrame(x: -2000, y: 950, width: 352, height: 360)
        let a = FloatingGeometry.fit(saved, preferredID: "left", screens: [left,right])
        try check(a.x == -1920 && a.y == 720, "负坐标保留并限制上边缘")
        let b = FloatingGeometry.fit(saved, preferredID: "left", screens: [right])
        try check(b.x == 0 && b.y == 540, "拔掉左屏后回到可见区域")
        let small = PanelScreen(id: "small", frame: PanelFrame(x: 10, y: 20, width: 200, height: 180))
        let c = FloatingGeometry.fit(saved, preferredID: nil, screens: [small])
        try check(c == small.frame, "小屏幕缩到可见大小")
        try check(FloatingGeometry.fit(saved, preferredID: nil, screens: []) == saved, "无屏幕时不异常")
    }
}
