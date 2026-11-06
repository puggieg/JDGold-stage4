import Foundation

public struct SelfTestFailure: Error, CustomStringConvertible { public var description: String }
public struct SelfTestCase { public var name: String; public var run: () throws -> Void }
// 自定义抛错断言在 -O 下仍执行，不用会被优化删除的 assert。
public enum CoreSelfTests {
    private static let day = Date(timeIntervalSince1970: 43200)
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SelfTestFailure(description: message) }
    }
    private static func state(quiet: Bool = false) -> AlertState {
        var value = AlertState(); value.quietHours = QuietHours(enabled: quiet); return value
    }
    private static func quote(_ price: Double, stale: Bool = false) -> GoldPrices {
        var info = PriceInfo(price: String(price)); info.isStale = stale
        return GoldPrices(values: [.minsheng: info])
    }
    private static func rule(_ direction: AlertDirection = .up, price: Double = 1000,
                             policy: RepeatPolicy = .everyCrossing, step: Double? = nil) -> AlertRule {
        AlertRule(id: "test", instrument: .minsheng, direction: direction, price: price, repeatPolicy: policy, trailingStep: step)
    }
    private static func breaches(_ events: [AlertEvent]) -> Int { events.filter { $0.kind == .breach }.count }
    public static var cases: [SelfTestCase] {
        [SelfTestCase(name: "首次突破", run: first),
         SelfTestCase(name: "震荡与缓冲边界", run: oscillation),
         SelfTestCase(name: "回撤重新激活", run: rearm),
         SelfTestCase(name: "跳空越过多档", run: gap),
         SelfTestCase(name: "独立规则顺延", run: trailing),
         SelfTestCase(name: "旧版追踪兼容", run: legacyTrailing),
         SelfTestCase(name: "免打扰与单条汇总", run: quiet),
         SelfTestCase(name: "下破对称", run: downward),
         SelfTestCase(name: "仅一次和持续提醒", run: policies),
         SelfTestCase(name: "纯函数与无效行情", run: purity),
         SelfTestCase(name: "五十旧键一次性迁移", run: migration),
         SelfTestCase(name: "JSON损坏保护与整组保存", run: storage),
         SelfTestCase(name: "钥匙串迁移失败保护", run: credentials),
         SelfTestCase(name: "数据源解析和输入校验", run: parsing),
         SelfTestCase(name: "行情缓存与退避", run: ServiceSelfTests.runBlocking)] + PresentationSelfTests.cases + DecisionFeatureSelfTests.cases
    }
    @discardableResult public static func runAll() -> Int {
        var failed = 0
        for test in cases {
            do { try test.run(); print("通过：\(test.name)") }
            catch { failed += 1; print("失败：\(test.name)：\(error)") }
        }
        print("\(cases.count - failed)/\(cases.count) 项通过")
        return failed
    }
    private static func first() throws {
        let a = AlertEngine.evaluate(price: quote(1000), rules: [rule()], state: state(), now: day)
        try expect(breaches(a.events) == 1, "恰好到价应触发")
        let b = AlertEngine.evaluate(price: quote(1001), rules: [rule()], state: a.newState, now: day.addingTimeInterval(86400))
        try expect(b.events.isEmpty, "默认不能持续提醒")
    }
    private static func oscillation() throws {
        var current = state(); var count = 0
        for price in [1000.0,999.9,1000.1,999.0,1000.0] {
            let result = AlertEngine.evaluate(price: quote(price), rules: [rule()], state: current, now: day)
            current = result.newState; count += breaches(result.events)
        }
        try expect(count == 1, "缓冲内与精确边界不能重激活")
        try expect(!AlertEngine.beyondBuffer(price: 1001, target: 1000, direction: .down, buffer: 0.001), "浮点边界容差")
    }
    private static func rearm() throws {
        var current = state(); var count = 0
        for price in [1000.0,998.9,1000.0] {
            let result = AlertEngine.evaluate(price: quote(price), rules: [rule()], state: current, now: day)
            current = result.newState; count += breaches(result.events)
        }
        try expect(count == 2, "安全回撤后应再次提醒")
    }
    private static func gap() throws {
        let rules = [990.0,1000,1010,1020,1030].enumerated().map {
            AlertRule(id: "slot\($0.offset)", instrument: .minsheng, direction: .up, price: $0.element, legacySlot: $0.offset)
        }
        let a = AlertEngine.evaluate(price: quote(1040), rules: rules, state: state(), now: day)
        try expect(breaches(a.events) == 5, "不能漏掉跳空越过的档位")
        try expect(AlertEngine.evaluate(price: quote(1041), rules: rules, state: a.newState, now: day).events.isEmpty, "不能重复提醒")
    }
    private static func trailing() throws {
        let a = AlertEngine.evaluate(price: quote(1000), rules: [rule(step: 5)], state: state(), now: day)
        try expect(a.newState.targetUpdates["test"] == 1005, "向上加幅度")
        try expect(a.events.contains { $0.kind == .targetShift && $0.oldTarget == 1000 && $0.newTarget == 1005 }, "说明旧价和新价")
        var shifted = rule(step: 5); shifted.price = 1005
        let b = AlertEngine.evaluate(price: quote(1001), rules: [shifted], state: a.newState, now: day)
        try expect(b.events.isEmpty, "新目标未到不能再顺延")
        let down = AlertEngine.evaluate(price: quote(1000), rules: [rule(.down,step: 5)], state: state(), now: day)
        try expect(down.newState.targetUpdates["test"] == 995, "向下减幅度")
        let invalid = AlertEngine.evaluate(price: quote(1), rules: [rule(.down,price: 1,step: 5)], state: state(), now: day)
        try expect(invalid.newState.targetUpdates.isEmpty, "不得写入非正目标")
        let message = AlertEvent(kind: .message, identity: "msg", title: "测试", body: "测试")
        let unrelated = AlertEngine.evaluateMessage(message, state: a.newState, now: day)
        try expect(unrelated.newState.targetUpdates.isEmpty, "普通消息不重放旧顺延")
    }
    private static func legacyTrailing() throws {
        let rules = [990.0,1000,1010].enumerated().map {
            AlertRule(id: "old\($0.offset)", instrument: .minsheng, direction: .up, price: $0.element,
                      trailingStep: 5, legacySlot: $0.offset, trailingBehavior: .legacyLadder)
        }
        let a = AlertEngine.evaluate(price: quote(1020), rules: rules, state: state(), now: day)
        try expect(a.newState.targetUpdates == ["old1":1015], "只顺延次极端档")
        try expect(AlertEngine.evaluate(price: quote(990), rules: rules, state: state(), now: day).newState.targetUpdates.isEmpty, "单旧档不顺延")
    }
    private static func quiet() throws {
        let night = Date(timeIntervalSince1970: 23*3600)
        let a = AlertEngine.evaluate(price: quote(1000), rules: [rule(step: 5)], state: state(quiet: true), now: night)
        try expect(a.events.count == 2 && a.events.allSatisfy { $0.delivery == .recordOnly }, "突破和顺延都应静音")
        try expect(a.newState.pending.count == 2, "待汇总记录保留")
        let morning = Date(timeIntervalSince1970: (24+8)*3600)
        let b = AlertEngine.evaluate(price: GoldPrices(), rules: [rule()], state: a.newState, now: morning)
        try expect(b.events.count == 1 && b.events[0].kind == .quietSummary, "结束只汇总一条")
        try expect(AlertEngine.evaluate(price: GoldPrices(), rules: [rule()], state: b.newState, now: morning).events.isEmpty, "不重复汇总")
        let hours = QuietHours()
        for minute in 0..<1440 {
            try expect(hours.contains(Date(timeIntervalSince1970: Double(minute*60))) == (minute >= 1380 || minute < 480), "跨午夜分钟枚举")
        }
        try expect(!QuietHours(startMinute: 0,endMinute: 0).contains(night), "同起止时刻关闭区间")
        try expect(QuietHours(startMinute: 600,endMinute: 900).contains(Date(timeIntervalSince1970: 600*60)), "开始包含")
        try expect(!QuietHours(startMinute: 600,endMinute: 900).contains(Date(timeIntervalSince1970: 900*60)), "结束不包含")
    }
    private static func downward() throws {
        var current = state(); var count = 0
        for price in [1000.0,1000.1,1000.0,1001.0,1000.0,1001.1,1000.0] {
            let result = AlertEngine.evaluate(price: quote(price), rules: [rule(.down)], state: current, now: day)
            current = result.newState; count += breaches(result.events)
        }
        try expect(count == 2, "下破对称回撤")
    }
    private static func policies() throws {
        let once = rule(policy: .once)
        let a = AlertEngine.evaluate(price: quote(1000), rules: [once], state: state(), now: day)
        let b = AlertEngine.evaluate(price: quote(998), rules: [once], state: a.newState, now: day)
        try expect(AlertEngine.evaluate(price: quote(1000), rules: [once], state: b.newState, now: day).events.isEmpty, "仅一次不回撤重激活")
        let repeated = rule(policy: .continuous(interval: 1800))
        let c = AlertEngine.evaluate(price: quote(1000), rules: [repeated], state: state(), now: day)
        let early = AlertEngine.evaluate(price: quote(1001), rules: [repeated], state: c.newState, now: day.addingTimeInterval(1799))
        let due = AlertEngine.evaluate(price: quote(1001), rules: [repeated], state: early.newState, now: day.addingTimeInterval(1800))
        try expect(early.events.isEmpty && breaches(due.events) == 1, "持续提醒间隔")
    }
    private static func purity() throws {
        let original = state()
        let a = AlertEngine.evaluate(price: quote(1000), rules: [rule()], state: original, now: day)
        let b = AlertEngine.evaluate(price: quote(1000), rules: [rule()], state: original, now: day)
        try expect(a.events == b.events && a.newState == b.newState && original.rules.isEmpty, "确定性且不修改输入")
        try expect(AlertEngine.evaluate(price: quote(1000,stale: true), rules: [rule()], state: original, now: day).events.isEmpty, "延迟不触发")
        try expect(AlertEngine.evaluate(price: quote(.nan), rules: [rule()], state: original, now: day).events.isEmpty, "无效价不触发")
        var disabled = rule(); disabled.enabled = false
        try expect(AlertEngine.evaluate(price: quote(1000), rules: [disabled], state: original, now: day).events.isEmpty, "禁用规则")
    }
    private static func withDefaults(_ operation: (UserDefaults) throws -> Void) throws {
        let suite = "JDGold.Selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try operation(defaults)
    }
    private static func migration() throws {
        try withDefaults { defaults in
            for instrument in Instrument.alertInstruments {
                defaults.set(instrument.group == .domestic ? 5.0 : 50.0, forKey: instrument.legacyStepKey)
                for direction in AlertDirection.allCases {
                    for slot in 0..<5 { defaults.set(1000.0+Double(slot), forKey: "target_\(direction.rawValue)_\(instrument.rawValue)_\(slot)") }
                }
            }
            let store = try AlertStore(defaults: defaults)
            try expect(store.rules.count == 50 && Set(store.rules.map { $0.id }).count == 50, "五十规则且ID唯一")
            try expect(store.rules.allSatisfy { $0.trailingStep == ($0.instrument.group == .domestic ? 5 : 50) && $0.trailingBehavior == .legacyLadder }, "幅度与兼容策略")
            let original = store.rules
            defaults.set(9999, forKey: "target_up_minsheng_0")
            let reopened = try AlertStore(defaults: defaults)
            try expect(reopened.rules == original, "已有JSON不重复导入")
            try reopened.save([])
            let empty = try AlertStore(defaults: defaults)
            try expect(empty.rules.isEmpty, "清空后不恢复旧规则")
        }
        try withDefaults { defaults in
            defaults.set(0, forKey: "target_up_minsheng_0"); defaults.set(-1, forKey: "target_up_minsheng_1")
            defaults.set(1000, forKey: "target_down_minsheng_4")
            let store = try AlertStore(defaults: defaults)
            try expect(store.rules.count == 1 && store.rules[0].legacySlot == 4, "仅正值，保留空档位置")
        }
    }
    private static func storage() throws {
        try withDefaults { defaults in
            let corrupt = Data("invalid-json".utf8); defaults.set(corrupt, forKey: AlertStore.rulesKey)
            do { _ = try AlertStore(defaults: defaults); throw SelfTestFailure(description: "损坏JSON不得覆盖") }
            catch is AlertStoreError {}
            try expect(defaults.data(forKey: AlertStore.rulesKey) == corrupt, "保留损坏原文")
        }
        try withDefaults { defaults in
            defaults.set(true, forKey: AlertStore.migrationKey)
            do { _ = try AlertStore(defaults: defaults); throw SelfTestFailure(description: "迁移后丢失JSON应阻止重复迁移") }
            catch is AlertStoreError {}
        }
        try withDefaults { defaults in
            let store = try AlertStore(defaults: defaults)
            var original = rule(); original.legacySlot = 0; original.note = "保留备注"
            try store.save([original])
            try store.updateEditor(sections: [EditedInstrument(instrument: .minsheng, upPrices: [1005,0,0,0,0], downPrices: [0,0,0,0,0])], steps: [.domestic:5])
            try expect(store.rules[0].id == original.id && store.rules[0].note == original.note, "保留ID及备注")
            let before = defaults.data(forKey: AlertStore.rulesKey)
            var invalid = original; invalid.price = .nan
            do { try store.save([invalid]); throw SelfTestFailure(description: "无效规则应拒绝保存") }
            catch is AlertStoreError {}
            try expect(defaults.data(forKey: AlertStore.rulesKey) == before, "失败不部分覆盖")
            var once = original; once.repeatPolicy = .once; try store.save([once])
            var current = state(); var runtime = RuleRuntime(); runtime.hasFired = true; current.rules[once.id] = runtime
            store.saveOnceState(current)
            try expect(store.consumedOnceRules().contains(once.id), "一次性消费状态持久化")
            store.saveOnceState(state()); try expect(store.consumedOnceRules().isEmpty, "编辑重置消费状态")
        }
    }
    private final class FakeSecrets: SecretStore {
        var value: String?; var failSave = false
        func read() throws -> String? { value }
        func save(_ value: String) throws { if failSave { throw CredentialError.verificationFailed }; self.value = value }
        func delete() throws { value = nil }
    }
    private static func credentials() throws {
        try withDefaults { defaults in
            let secrets = FakeSecrets(); let credentials = BarkCredentials(secrets: secrets, defaults: defaults)
            defaults.set("test-only-key", forKey: "userBarkKey"); secrets.failSave = true
            do { _ = try credentials.loadAndMigrate(); throw SelfTestFailure(description: "失败应返回错误") }
            catch is CredentialError {}
            try expect(defaults.string(forKey: "userBarkKey") == "test-only-key", "失败不删明文")
            secrets.failSave = false
            let migrated = try credentials.loadAndMigrate()
            try expect(migrated == "test-only-key" && defaults.object(forKey: "userBarkKey") == nil, "成功才删明文")
            defaults.set("old-key", forKey: "userBarkKey")
            let current = try credentials.loadAndMigrate(); try expect(current == "test-only-key", "钥匙串已有值优先")
            try credentials.save(nil); try expect(secrets.value == nil, "解绑删除")
        }
    }
    private static func parsing() throws {
        let providers: [any PriceProvider] = [MinshengProvider(), ICBCProvider(), ZheshangProvider(), SinaProvider(), EastmoneyProvider()]
        let requests = try providers.map { try $0.makeRequest() }
        try expect(requests[0].httpMethod == "GET" && requests[1].httpMethod == "POST" && requests[2].httpMethod == "POST", "保持请求方法")
        try expect(requests[1].url?.query == "productSku=2005453243" && requests[2].url?.query == "productSku=1961543816", "保持原参数")
        let fixture = "var hq_str_hf_GC=\"4171.890,,4172.300,4172.600,4193.500,4165.500,15:54:39,4177.300,4184.200,0,3,2,2026-10-14,纽约黄金,0\";"
        let info = try SinaProvider().parse(Data(fixture.utf8)).prices[.newyork]
        try expect(info?.yesterdayPrice == "4177.30" && info?.changeAmount == "-5.41", "取原parts[7]昨收")
        try expect(parsePriceInput("１，２３４．５６") == 1234.56 && parsePriceInput("８００，５") == 800.5, "全角与逗号")
        try expect(parsePriceInput("abc") == nil && parsePriceInput("1,2,3") == nil, "非法输入")
        for text in ["A/B?C#D&E", "金价 / ? # &"] {
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            try expect(encoded.removingPercentEncoding == text && !encoded.contains("/") && !encoded.contains("?") && !encoded.contains("#") && !encoded.contains("&"), "编码可逆且无分隔符")
        }
    }
}
