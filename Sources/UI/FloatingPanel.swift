#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

@MainActor final class FloatingWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class FloatingQuoteRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let price = NSTextField(labelWithString: "--")
    private let badge = NSTextField(labelWithString: "—")
    private let flash = NSView()
    private let premiumLabel = NSTextField(labelWithString: "")
    private let sparkline = TodaySparklineView(frame: .zero)
    private let rangeLabel = NSTextField(wrappingLabelWithString: "")
    private var showHistory = true
    private var isDomestic = false
    private var lastPrice: Double?
    private var generation = 0
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        flash.wantsLayer = true; flash.layer?.cornerRadius = 8; flash.alphaValue = 0; addSubview(flash)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        price.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold); price.alignment = .right
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium); badge.alignment = .center
        badge.wantsLayer = true; badge.layer?.cornerRadius = 8
        for field in [name,price,badge,premiumLabel,rangeLabel] { addSubview(field) }
        premiumLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); premiumLabel.textColor = .secondaryLabelColor
        rangeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); rangeLabel.textColor = .secondaryLabelColor
        rangeLabel.maximumNumberOfLines = 2; rangeLabel.alignment = .right
        addSubview(sparkline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout(); flash.frame = bounds
        name.frame = NSRect(x: 8, y: bounds.height - 24, width: 80, height: 16)
        price.frame = NSRect(x: 96, y: bounds.height - 28, width: 112, height: 24)
        badge.frame = NSRect(x: 216, y: bounds.height - 24, width: max(72, bounds.width - 224), height: 16)
        premiumLabel.frame = NSRect(x: 8, y: bounds.height - 44, width: bounds.width - 16, height: 16)
        sparkline.frame = NSRect(x: 8, y: 4, width: 176, height: 24)
        rangeLabel.frame = NSRect(x: 208, y: 4, width: max(120, bounds.width - 216), height: 24)
    }
    func update(instrument: Instrument, info: PriceInfo, premium: DomesticPremium?, samples: [MinutePriceSample], showHistory: Bool, now: Date) {
        self.showHistory = showHistory; isDomestic = instrument.group == .domestic
        premiumLabel.stringValue = premium?.displayText ?? ""; premiumLabel.isHidden = premium == nil
        premiumLabel.toolTip = TodayHistoryPresentation.premiumTooltip(premium)
        sparkline.isHidden = !showHistory; rangeLabel.isHidden = !showHistory
        rangeLabel.stringValue = TodayHistoryPresentation.rangeText(samples)
        rangeLabel.toolTip = "高低为今日已采集报价，不包含启动前或缺失时段。"
        name.stringValue = instrument.displayName; price.stringValue = info.price
        let delayed = MarketPresentation.isDelayed(info, now: now)
        price.textColor = delayed ? .secondaryLabelColor : .labelColor
        sparkline.update(samples: samples, delayed: delayed)
        let color = info.movementColor(now: now)
        badge.stringValue = MarketPresentation.movement(info); badge.textColor = color
        effectiveAppearance.performAsCurrentDrawingAppearance { self.badge.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor }
        toolTip = "\(instrument.unit) · \(info.sourceDescription(now: now))" + (isDomestic ? " · " + TodayHistoryPresentation.premiumTooltip(premium) : "")
        if info.isValid && !info.isStale {
            if let previous = lastPrice, previous != info.doublePrice {
                generation += 1
                let currentGeneration = generation
                let changedColor: NSColor = info.doublePrice > previous ? .systemRed : .systemGreen
                effectiveAppearance.performAsCurrentDrawingAppearance { self.flash.layer?.backgroundColor = changedColor.withAlphaComponent(0.16).cgColor }
                flash.alphaValue = 1
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.6
                    self.flash.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.generation == currentGeneration else { return }
                        self.flash.alphaValue = 0
                    }
                })
            }
            lastPrice = info.doublePrice
        }
    }
}
@MainActor private final class FloatingRowsView: NSView { override var isFlipped: Bool { true } }

@MainActor final class FloatingContentView: NSVisualEffectView {
    private let title = NSTextField(labelWithString: "JDGold")
    private let pin = NSButton()
    private let closeButton = NSButton()
    private let footer = NSTextField(labelWithString: "")
    private let bodyScroll = NSScrollView()
    private let bodyView = FloatingRowsView()
    private var tracking: NSTrackingArea?
    private var rows: [Instrument: FloatingQuoteRow] = [:]
    private var headers: [NSTextField] = []
    private var mini = false
    private var selected: Instrument = .minsheng
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        footer.font = .systemFont(ofSize: 10); footer.textColor = .secondaryLabelColor
        configureButton(pin, symbol: "pin", label: "固定位置", action: #selector(pinClicked))
        configureButton(closeButton, symbol: "xmark", label: "关闭悬浮窗", action: #selector(closeClicked))
        for view in [title, footer, pin, closeButton] { addSubview(view) }
        // 完整走势更高；在小屏幕或多屏可见区收缩后仍能滚动查看全部品种。
        bodyScroll.drawsBackground = false; bodyScroll.hasVerticalScroller = true; bodyScroll.autohidesScrollers = true
        bodyScroll.documentView = bodyView; addSubview(bodyScroll)
        rebuild(mini: false, selected: .minsheng)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly; button.isBordered = false; button.toolTip = label
        button.target = self; button.action = action; button.alphaValue = 0
    }
    func configure(mini: Bool, selected: Instrument, pinned: Bool) {
        if self.mini != mini || self.selected != selected { rebuild(mini: mini, selected: selected) }
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "固定位置")
        title.stringValue = mini ? selected.displayName : "JDGold"
    }
    private func rebuild(mini: Bool, selected: Instrument) {
        self.mini = mini; self.selected = selected
        for row in rows.values { row.removeFromSuperview() }; rows.removeAll()
        for header in headers { header.removeFromSuperview() }; headers.removeAll()
        for instrument in (mini ? [selected] : Instrument.allCases) {
            let row = FloatingQuoteRow(frame: .zero); rows[instrument] = row; bodyView.addSubview(row)
        }
        if !mini {
            for text in ["国内积存金 · 元/克", "国际金价 · $/oz", "参考指标"] {
                let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: 10); field.textColor = .secondaryLabelColor
                headers.append(field); bodyView.addSubview(field)
            }
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        title.frame = NSRect(x: 16, y: bounds.height - 32, width: 224, height: 16)
        pin.frame = NSRect(x: bounds.width - 72, y: bounds.height - 36, width: 24, height: 24)
        closeButton.frame = NSRect(x: bounds.width - 40, y: bounds.height - 36, width: 24, height: 24)
        bodyScroll.frame = NSRect(x: 0, y: 40, width: bounds.width, height: max(32, bounds.height - 80))
        let contentHeight: CGFloat = mini ? (selected.group == .domestic ? 48 : 32) : 516
        bodyView.frame = NSRect(x: 0, y: 0, width: bodyScroll.contentSize.width, height: max(contentHeight, bodyScroll.contentSize.height))
        var y: CGFloat = 0
        if mini { rows[selected]?.frame = NSRect(x: 8, y: y, width: bodyView.bounds.width - 16, height: contentHeight) }
        else {
            for (index, group) in [Instrument.Group.domestic, .international, .index].enumerated() {
                headers[index].frame = NSRect(x: 16, y: y, width: bodyView.bounds.width - 32, height: 16); y += 20
                for instrument in Instrument.allCases where instrument.group == group {
                    let height: CGFloat = group == .domestic ? 80 : 64
                    rows[instrument]?.frame = NSRect(x: 8, y: y, width: bodyView.bounds.width - 16, height: height); y += height
                }
                y += 8
            }
        }
        footer.frame = NSRect(x: 16, y: 12, width: bounds.width - 32, height: 16)
    }
    func update(prices: GoldPrices, rate: ExchangeRate?, history: TodayPriceHistory, now: Date) {
        for (instrument, row) in rows {
            let premium = instrument.group == .domestic ? PremiumCalculator.calculate(domestic: prices.priceInfo(for: instrument), london: prices.priceInfo(for: .london), rate: rate, now: now) : nil
            row.update(instrument: instrument, info: prices.priceInfo(for: instrument), premium: premium,
                       samples: history.samples(for: instrument, now: now), showHistory: !mini, now: now)
        }
        let infos = rows.keys.map { prices.priceInfo(for: $0) }
        let latest = infos.compactMap { $0.sourceUpdatedAt }.max()
        footer.stringValue = latest.map { "来源 \(DisplayFormatters.sourceText($0)) 北京时间" } ?? "来源时间未提供"
        if infos.contains(where: { MarketPresentation.isDelayed($0, now: now) }) { footer.stringValue += " · 休市/延迟" }
        footer.toolTip = footer.stringValue + " · 今日采集走势以北京时间分日，高低不包含启动前或缺失时段。"
        if !mini { title.stringValue = "JDGold · 今日采集走势" }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { pin.alphaValue = 1; closeButton.alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { pin.alphaValue = 0; closeButton.alphaValue = 0 }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
    @objc private func pinClicked() { onPin?() }
    @objc private func closeClicked() { onClose?() }
}
