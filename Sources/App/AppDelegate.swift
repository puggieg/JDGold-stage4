#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var quoteRows: [Instrument: QuoteMenuRow] = [:]
    var rulesMenuItem: NSMenuItem?
    var floatingMenuItem: NSMenuItem?
    var prices = GoldPrices()
    var exchangeRate: ExchangeRate?
    var todayHistory = TodayPriceHistory(day: MarketDay.key(Date()))
    let exchangeRateService = ExchangeRateService(log: { source, message in appLog(source, message) })
    lazy var historyStore: TodayHistoryStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.jd.goldprice", isDirectory: true)
        return TodayHistoryStore(fileURL: directory.appendingPathComponent("today-prices.json"), log: { source, message in appLog(source, message) })
    }()
    var refreshTimer: Timer?
    var isRefreshing = false
    var engineState = AlertState()
    var activityToken: NSObjectProtocol?
    let model = SettingsModel()
    let settingsController = SettingsWindowController()
    lazy var floatingController = FloatingPanelController(model: model)
    let alertWindowController = AlertWindowController()
    let systemNotificationService = SystemNotificationService()
    let barkService = BarkNotificationService()
    lazy var credentialService = BarkCredentialService(service: (Bundle.main.bundleIdentifier ?? "com.jd.goldprice") + ".Bark")
    let priceService = PriceService(log: { source, message in appLog(source, message) })
    var barkKey: String?
    var barkQuery: String?
    private var credentialsReady = false
    private var terminationSavePending = false
    private var terminationSaveFinished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let store = model.alertStore {
            do { engineState.pending = try store.loadPending() }
            catch { appLog("规则存储", "汇总读取失败：\(error)") }
            for id in store.consumedOnceRules() { var runtime = RuleRuntime(); runtime.hasFired = true; engineState.rules[id] = runtime }
        }
        configureEngine(); barkQuery = model.defaults.string(forKey: "userBarkQuery")
        bindSettings()
        // FIX(B4): 防止 App Nap，不禁止系统空闲睡眠。
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "监控金价并推送预警")
        setupStatusItem(); setupMenu()
        systemNotificationService.refreshStatus(model); LoginItemService.refresh(model)
        startRefreshing()
        Task { @MainActor in
            do { barkKey = try await credentialService.load() }
            catch {
                appLog("钥匙串", "读取或迁移失败，旧配置已保留")
                barkKey = model.defaults.string(forKey: "userBarkKey")
            }
            credentialsReady = true; model.barkBusy = false
            model.barkStatus = barkKey.map { "已绑定 ••••" + String($0.suffix(4)) } ?? "尚未绑定"
            flushQuietNotificationsIfNeeded(); checkPricesForAlert()
        }
    }
    private func bindSettings() {
        model.onIntervalChange = { [weak self] in self?.startRefreshing() }
        model.onAppearanceChange = { [weak self] in self?.updateUI() }
        model.onNotificationChange = { [weak self] in guard let self = self else { return }; self.systemNotificationService.refreshStatus(self.model) }
        model.onRulesChanged = { [weak self] ids in
            guard let self = self else { return }
            for id in ids { self.engineState.reset(ruleID: id) }
            self.model.alertStore?.saveOnceState(self.engineState)
            self.model.refreshRules(); self.updateUI(); self.checkPricesForAlert()
        }
        model.onRequestNotification = { [weak self] in guard let self = self else { return }; self.systemNotificationService.requestPermission(self.model) }
        model.onLoginChange = { [weak self] enabled in guard let self = self else { return }; LoginItemService.setEnabled(enabled, model: self.model) }
        model.onSaveBark = { [weak self] link in
            guard let self = self else { return }
            // 先确认写入钥匙串，再替换内存和参数，失败不覆盖原绑定。
            try await self.credentialService.save(link?.key)
            self.barkKey = link?.key; self.barkQuery = link?.query
            self.model.defaults.set(link?.query, forKey: "userBarkQuery")
        }
        model.onTestBark = { [weak self] in
            guard let self = self else { return "应用已退出。" }
            guard let key = self.barkKey, !key.isEmpty else { return "尚未绑定 Bark，请先保存链接。" }
            self.configureEngine()
            if self.engineState.quietHours.contains(Date()) {
                let event = AlertEvent(kind: .message, identity: "bark-test", title: "Bark 测试", body: "JDGold 测试提醒")
                self.acceptEngineResult(AlertEngine.evaluateMessage(event, state: self.engineState, now: Date()))
                return "当前为免打扰时段，测试已记录，结束后随汇总推送。"
            }
            return await self.barkService.send(key: key, query: self.barkQuery, title: "JDGold 测试", body: "手机推送已连接 / ? # &")
        }
        model.onCheckUpdate = { [weak self] in Task { await self?.performUpdateCheck() } }
    }
    func startRefreshing() {
        refreshTimer?.invalidate()
        Task { await refreshPrices() }
        // FIX(B1): common + modalPanel 模式保证菜单和 runModal 打开期间继续刷新。
        let timer = Timer(timeInterval: model.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.flushQuietNotificationsIfNeeded(); self.updateUI(); await self.refreshPrices()
            }
        }
        refreshTimer = timer; RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel)
    }
    func refreshPrices() async {
        guard !terminationSavePending else { return }
        flushQuietNotificationsIfNeeded()
        // FIX(B7): 手动和定时刷新共享同一防重入门闩。
        guard !isRefreshing else { return }; isRefreshing = true; defer { isRefreshing = false }
        // 先恢复本地记录，再并发抓取原行情和新增汇率；汇率不参与预警判定。
        todayHistory = await historyStore.snapshot(now: Date()); updateUI()
        // 子任务只捕获可安全跨线程使用的 actor，不捕获整个 UI 代理。
        let priceSource = priceService, rateSource = exchangeRateService
        async let fetchedPrices = priceSource.fetchAllPrices()
        async let fetchedRate = rateSource.fetch()
        prices = await fetchedPrices; updateUI(); checkPricesForAlert()
        // 预警不等待磁盘保存和较慢的汇率请求。
        todayHistory = await historyStore.record(prices, now: Date()); updateUI()
        exchangeRate = await fetchedRate; updateUI()
    }
    func checkPricesForAlert() {
        // 等钥匙串读取完成再消费规则，避免首次突破时漏掉手机推送。
        guard !terminationSavePending, credentialsReady, let store = model.alertStore else { return }
        configureEngine(); acceptEngineResult(AlertEngine.evaluate(price: prices, rules: store.rules, state: engineState, now: Date()))
    }
    func flushQuietNotificationsIfNeeded() {
        guard !terminationSavePending, credentialsReady, let store = model.alertStore else { return }
        configureEngine()
        acceptEngineResult(AlertEngine.evaluate(price: GoldPrices(), rules: store.rules, state: engineState, now: Date()))
    }
    func configureEngine() {
        engineState.bufferRatio = model.defaults.double(forKey: "alertRearmBufferRatio")
        engineState.quietHours = QuietHours(enabled: model.quietEnabled, startMinute: model.quietStart,
                                           endMinute: model.quietEnd, timeZoneIdentifier: TimeZone.current.identifier)
    }
    func acceptEngineResult(_ result: (events: [AlertEvent], newState: AlertState)) {
        guard let store = model.alertStore else { return }
        do {
            // FIX(B11): 先写回顺延目标及免打扰记录，再通知用户，保证提示对应真实保存结果。
            try store.applyTargetUpdates(result.newState.targetUpdates); try store.savePending(result.newState.pending)
            store.saveOnceState(result.newState); engineState = result.newState; model.refreshRules()
        } catch { appLog("规则存储", "计算结果未提交：\(error)"); return }
        for event in result.events {
            if event.delivery == .recordOnly { appLog("免打扰", "已记录：\(event.body)"); continue }
            // 展示层替换上游 emoji，纯引擎与持久化格式保持原样。
            let title = cleanText(event.title), body = cleanText(event.body)
            systemNotificationService.deliver(title: title, body: body, preferSystem: model.systemNotifications, sound: model.soundEnabled) { [weak self] in
                guard let self = self else { return }; self.alertWindowController.showAlert(title: title, body: body, sound: self.model.soundEnabled)
            }
            let key = barkKey, query = barkQuery
            if key != nil { Task { _ = await barkService.send(key: key, query: query, title: title, body: body) } }
        }
        rulesMenuItem?.title = "预警规则（\(model.activeRuleCount) 条生效中）"
    }
    private func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "📈", with: "▲").replacingOccurrences(of: "📉", with: "▼")
            .replacingOccurrences(of: "🔔", with: "").replacingOccurrences(of: "🎯", with: "")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationSaveFinished { return .terminateNow }
        if terminationSavePending { return .terminateLater }
        terminationSavePending = true
        // 正常退出补写当前分钟的最终采样；异步等待，保持界面响应。
        Task { @MainActor in
            await historyStore.flush(now: Date())
            finishTermination(sender)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !terminationSaveFinished else { return }
            appLog("今日走势", "退出保存超时，可能缺少最后一分钟的采样")
            finishTermination(sender)
        }
        return .terminateLater
    }
    private func finishTermination(_ sender: NSApplication) {
        guard !terminationSaveFinished else { return }
        terminationSaveFinished = true; sender.reply(toApplicationShouldTerminate: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate(); floatingController.saveFrame()
        if let token = activityToken { ProcessInfo.processInfo.endActivity(token) }; activityToken = nil
    }
}
