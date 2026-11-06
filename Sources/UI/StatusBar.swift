#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

@MainActor final class QuoteMenuRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let price = NSTextField(labelWithString: "--")
    private let movement = NSTextField(labelWithString: "—")
    private let minimum = NSTextField(labelWithString: "最低")
    private let source = NSTextField(labelWithString: "")
    private let premiumLabel = NSTextField(labelWithString: "")
    private let sparkline = TodaySparklineView(frame: .zero)
    private let rangeLabel = NSTextField(wrappingLabelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        price.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); price.alignment = .right
        movement.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); movement.alignment = .right
        minimum.font = .systemFont(ofSize: 10, weight: .medium); minimum.textColor = .secondaryLabelColor
        source.font = .systemFont(ofSize: 10); source.textColor = .secondaryLabelColor
        name.frame = NSRect(x: 16, y: frame.height - 24, width: 80, height: 16)
        minimum.frame = NSRect(x: 96, y: frame.height - 24, width: 32, height: 16)
        price.frame = NSRect(x: 128, y: frame.height - 24, width: 112, height: 16)
        movement.frame = NSRect(x: 248, y: frame.height - 24, width: 104, height: 16)
        source.frame = NSRect(x: 16, y: frame.height - 44, width: 352, height: 16)
        premiumLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); premiumLabel.textColor = .secondaryLabelColor
        premiumLabel.frame = NSRect(x: 16, y: 32, width: 352, height: 16); premiumLabel.isHidden = true
        sparkline.frame = NSRect(x: 16, y: 4, width: 168, height: 24)
        rangeLabel.frame = NSRect(x: 200, y: 4, width: 168, height: 24)
        rangeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); rangeLabel.textColor = .secondaryLabelColor
        rangeLabel.maximumNumberOfLines = 2; rangeLabel.alignment = .right
        addSubview(premiumLabel); addSubview(sparkline); addSubview(rangeLabel)
        for field in [name,price,movement,minimum,source] { addSubview(field) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(instrument: Instrument, info: PriceInfo, lowest: Bool, premium: DomesticPremium?, samples: [MinutePriceSample], now: Date) {
        name.stringValue = instrument.displayName; price.stringValue = "\(info.price) \(instrument.unit)"
        let delayed = MarketPresentation.isDelayed(info, now: now)
        price.textColor = delayed ? .secondaryLabelColor : .labelColor
        movement.stringValue = MarketPresentation.movement(info); movement.textColor = info.movementColor(now: now)
        minimum.isHidden = !lowest; source.stringValue = info.sourceDescription(now: now)
        premiumLabel.stringValue = premium?.displayText ?? ""; premiumLabel.isHidden = premium == nil
        premiumLabel.toolTip = TodayHistoryPresentation.premiumTooltip(premium)
        sparkline.update(samples: samples, delayed: delayed); rangeLabel.stringValue = TodayHistoryPresentation.rangeText(samples)
        rangeLabel.toolTip = "高低为今日已采集报价的高低值，不包含启动前或缺失时段。"
        toolTip = source.stringValue + (instrument.group == .domestic ? " · " + TodayHistoryPresentation.premiumTooltip(premium) : "")
        setAccessibilityLabel("\(instrument.displayName)，\(price.stringValue)，\(movement.stringValue)，\(source.stringValue)")
    }
}

extension AppDelegate {
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "JDGold")
        image?.isTemplate = true; image?.size = NSSize(width: 16, height: 16)
        statusItem.button?.image = image; statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }
    func setupMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        for (heading, group) in [("国内积存金", Instrument.Group.domestic), ("国际金价", .international), ("参考指标", .index)] {
            let header = NSMenuItem(title: heading, action: nil, keyEquivalent: ""); header.isEnabled = false
            menu.addItem(header)
            for instrument in Instrument.allCases where instrument.group == group {
                let row = QuoteMenuRow(frame: NSRect(x: 0, y: 0, width: 384, height: instrument.group == .domestic ? 96 : 80))
                quoteRows[instrument] = row
                let item = NSMenuItem(title: instrument.displayName, action: nil, keyEquivalent: ""); item.view = row; menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let floating = NSMenuItem(title: "悬浮窗", action: nil, keyEquivalent: "")
        floating.submenu = floatingController.makeMenu(); floatingMenuItem = floating; menu.addItem(floating)
        menu.addItem(.separator())
        rulesMenuItem = actionItem("预警规则（0 条生效中）", #selector(showRules), "")
        // 菜单属性是可选值；解包后再交给要求非可选参数的 AppKit。
        if let item = rulesMenuItem { menu.addItem(item) }
        menu.addItem(actionItem("偏好设置…", #selector(showSettings), ","))
        menu.addItem(actionItem("立即刷新", #selector(manualRefresh), "r"))
        menu.addItem(actionItem("退出", #selector(quit), "q"))
        statusItem.menu = menu
        installApplicationMenu()
        updateUI()
    }
    private func actionItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self
        item.keyEquivalentModifierMask = .command; return item
    }
    private func installApplicationMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(title: "JDGold")
        appMenu.addItem(actionItem("偏好设置…", #selector(showSettings), ","))
        appMenu.addItem(actionItem("立即刷新", #selector(manualRefresh), "r"))
        appMenu.addItem(actionItem("退出", #selector(quit), "q")); appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; main.addItem(editItem)
        let windowItem = NSMenuItem(); let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭", action: NSSelectorFromString("performClose:"), keyEquivalent: "w"))
        windowItem.submenu = windowMenu; main.addItem(windowItem); NSApplication.shared.mainMenu = main
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.now = Date(); updateUI(); floatingMenuItem?.submenu = floatingController.makeMenu()
        systemNotificationService.refreshStatus(model); LoginItemService.refresh(model)
    }
    func updateUI() {
        let now = Date(); model.now = now; model.prices = prices
        let info = prices.priceInfo(for: model.statusInstrument)
        let prefix = model.statusInstrument == .usdIndex ? "DXY" : "Au"
        let title = NSMutableAttributedString(string: "\(prefix) \(info.price)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: MarketPresentation.isDelayed(info, now: now) ? NSColor.secondaryLabelColor : NSColor.labelColor])
        if model.showMovement {
            title.append(NSAttributedString(string: " \(MarketPresentation.movement(info))", attributes: [
                .foregroundColor: model.colorMovement ? info.movementColor(now: now) : NSColor.secondaryLabelColor]))
        }
        statusItem.button?.attributedTitle = title; statusItem.button?.toolTip = "\(model.statusInstrument.displayName) · \(info.sourceDescription(now: now))"
        let lowest = MarketPresentation.lowestBanks(prices, now: now)
        for (instrument, row) in quoteRows {
            let premium = instrument.group == .domestic ? PremiumCalculator.calculate(domestic: prices.priceInfo(for: instrument), london: prices.priceInfo(for: .london), rate: exchangeRate, now: now) : nil
            row.update(instrument: instrument, info: prices.priceInfo(for: instrument), lowest: lowest.contains(instrument),
                       premium: premium, samples: todayHistory.samples(for: instrument, now: now), now: now)
        }
        rulesMenuItem?.title = "预警规则（\(model.activeRuleCount) 条生效中）"
        floatingController.applySettings(); floatingController.update(prices: prices, rate: exchangeRate, history: todayHistory, now: now)
    }
    @objc func showSettings() { systemNotificationService.refreshStatus(model); LoginItemService.refresh(model); settingsController.show(model: model) }
    @objc func showRules() { settingsController.show(model: model, tab: 1) }
    @objc func manualRefresh() { Task { await refreshPrices() } }
    @objc func quit() { NSApplication.shared.terminate(nil) }
}
