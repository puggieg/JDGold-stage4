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
    private let range = TodayRangeView(frame: .zero)
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
        // 采集高与采集低各占一行；右侧问号常驻，不依赖点击才出现第二行。
        range.frame = NSRect(x: 200, y: 2, width: 168, height: 28)
        addSubview(premiumLabel); addSubview(sparkline); addSubview(range)
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
        sparkline.update(samples: samples, delayed: delayed)
        range.update(samples: samples)
        toolTip = source.stringValue + (instrument.group == .domestic ? " · " + TodayHistoryPresentation.premiumTooltip(premium) : "")
        setAccessibilityLabel("\(instrument.displayName)，\(price.stringValue)，\(movement.stringValue)，\(source.stringValue)")
    }
}

// 链接按钮自己画文字：NSButtonCell 在菜单高亮/焦点态会接管 attributedTitle 的前景色，
// 把它改成黑色。重写 draw 后颜色只由这里决定，任何状态下都是蓝色；事件处理仍沿用 NSButton。
@MainActor private final class BlueLinkButton: NSButton {
    var linkText = "显示其余银行金价"
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        refusesFirstResponder = true
        setAccessibilityLabel(linkText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setLinkText(_ text: String) {
        linkText = text
        title = text
        setAccessibilityLabel(text)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let text = NSAttributedString(string: linkText, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: 0, y: max(0, (bounds.height - size.height) / 2)))
    }
}

// 默认银行下方的单次展开/收起按钮。点击自定义视图不会让菜单自动关闭。
@MainActor final class ShowOtherBanksRow: NSView {
    private let button = BlueLinkButton(frame: .zero)
    var onToggle: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        button.target = self; button.action = #selector(clicked)
        button.frame = NSRect(x: 16, y: 2, width: 220, height: 20)
        addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func clicked() { onToggle?() }
    func setExpanded(_ expanded: Bool) { button.setLinkText(expanded ? "隐藏其余银行金价" : "显示其余银行金价") }
}

extension AppDelegate {
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 阶段五：不再使用系统图标，状态栏统一以 🧱 开头。
        statusItem.button?.image = nil
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }
    // 国内组默认只显示「显示品种」选中的那家银行；选中非银行品种时由纯函数回退到工商银行。
    private var defaultDomesticBank: Instrument { MenuBankPresentation.primary(model.statusInstrument) }
    private func menuInstruments(_ group: Instrument.Group) -> [Instrument] {
        guard group == .domestic else { return Instrument.allCases.filter { $0.group == group } }
        return MenuBankPresentation.domesticOrder(primary: defaultDomesticBank)
    }
    func setupMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        extraBankItems = []; showOtherBanksItem = nil
        let primary = defaultDomesticBank
        for (heading, group) in [("国内积存金", Instrument.Group.domestic), ("国际金价", .international), ("参考指标", .index)] {
            let header = NSMenuItem(title: heading, action: nil, keyEquivalent: ""); header.isEnabled = false
            menu.addItem(header)
            var primaryItem: NSMenuItem?
            for instrument in menuInstruments(group) {
                let row = QuoteMenuRow(frame: NSRect(x: 0, y: 0, width: 384, height: group == .domestic ? 96 : 80))
                quoteRows[instrument] = row
                let item = NSMenuItem(title: instrument.displayName, action: nil, keyEquivalent: "")
                item.view = row; menu.addItem(item)
                if group == .domestic && instrument == primary { primaryItem = item }
                if group == .domestic && instrument != primary { extraBankItems.append(item) }
            }
            if group == .domestic, let anchor = primaryItem {
                let row = ShowOtherBanksRow(frame: NSRect(x: 0, y: 0, width: 384, height: 24))
                row.onToggle = { [weak self] in
                    guard let self = self else { return }
                    self.showOtherBanksOnce.toggle(); self.applyBankVisibility()
                    // 菜单正处于跟踪状态时，显式 update 让隐藏/显示的菜单项立即重排。
                    self.statusItem.menu?.update()
                    self.updateUI()
                }
                showOtherBanksRow = row
                let item = NSMenuItem(title: "显示其余银行金价", action: nil, keyEquivalent: "")
                item.view = row; showOtherBanksItem = item
                // 紧跟默认银行之后：默认银行 → 展开按钮 → 其余两家。
                menu.insertItem(item, at: menu.index(of: anchor) + 1)
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
        applyBankVisibility(); updateUI()
    }
    // 两套逻辑：偏好设置常显示；展开按钮只作用于本次打开的菜单。
    func applyBankVisibility() {
        let visible = model.alwaysShowAllBanks || showOtherBanksOnce
        for item in extraBankItems { item.isHidden = !visible }
        showOtherBanksItem?.isHidden = model.alwaysShowAllBanks
        showOtherBanksRow?.setExpanded(showOtherBanksOnce)
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
        guard menu === statusItem.menu else { return }
        // 关闭后再次打开恢复默认：只显示「显示品种」选中的那家银行。
        showOtherBanksOnce = false; applyBankVisibility()
        model.now = Date(); updateUI(); floatingMenuItem?.submenu = floatingController.makeMenu()
        systemNotificationService.refreshStatus(model); LoginItemService.refresh(model)
    }
    func updateUI() {
        let now = Date(); model.now = now; model.prices = prices
        let info = prices.priceInfo(for: model.statusInstrument)
        let title = NSMutableAttributedString(string: "🧱 \(info.price)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: MarketPresentation.isDelayed(info, now: now) ? NSColor.secondaryLabelColor : NSColor.labelColor])
        if model.showMovement {
            title.append(NSAttributedString(string: " \(MarketPresentation.movement(info))", attributes: [
                .foregroundColor: model.colorMovement ? info.movementColor(now: now) : NSColor.secondaryLabelColor]))
        }
        statusItem.button?.attributedTitle = title; statusItem.button?.toolTip = "\(model.statusInstrument.displayName) · \(info.sourceDescription(now: now))"
        applyBankVisibility()
        let lowest = MarketPresentation.lowestBanks(prices, now: now)
        // 只显示一家时不声称「最低」；三家都可见才做横向比较。
        let comparable = model.alwaysShowAllBanks || showOtherBanksOnce
        for (instrument, row) in quoteRows {
            let premium = instrument.group == .domestic ? PremiumCalculator.calculate(domestic: prices.priceInfo(for: instrument), london: prices.priceInfo(for: .london), rate: exchangeRate, now: now) : nil
            row.update(instrument: instrument, info: prices.priceInfo(for: instrument), lowest: comparable && lowest.contains(instrument),
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
