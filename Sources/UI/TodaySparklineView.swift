#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

// 手绘迷你走势；坐标与缺口判断在纯模型中，NSBezierPath 只负责绘制。
@MainActor final class TodaySparklineView: NSView {
    private var samples: [MinutePriceSample] = []
    private var dimmed = false
    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(samples: [MinutePriceSample], delayed: Bool) {
        self.samples = samples; dimmed = delayed; needsDisplay = true
        let summary = SparklineGeometry.extremes(samples)
        let description = summary.map { String(format: "今日本机采集：高 %.2f，低 %.2f，%d 条分钟记录", $0.high, $0.low, samples.count) } ?? "今日尚无有效采样"
        toolTip = description + "；北京时间分日，空缺表示断网、休眠或未运行，不是交易所完整日线。"
        setAccessibilityLabel(description)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let plot = bounds.insetBy(dx: 4, dy: 4)
        guard plot.width > 0, plot.height > 0 else { return }
        let points = SparklineGeometry.points(samples)
        guard !points.isEmpty else {
            let text = "今日暂无采样"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
            (text as NSString).draw(in: plot, withAttributes: attributes)
            return
        }
        let first = samples.first?.price ?? 0, last = samples.last?.price ?? 0
        let color: NSColor = dimmed || first == last ? .secondaryLabelColor : (last > first ? .systemRed : .systemGreen)
        color.setStroke(); color.setFill()
        let path = NSBezierPath(); path.lineWidth = 1.5; path.lineJoinStyle = .round; path.lineCapStyle = .round
        for point in points {
            let position = NSPoint(x: plot.minX + CGFloat(point.x) * plot.width, y: plot.minY + CGFloat(point.y) * plot.height)
            if point.startsSegment { path.move(to: position) } else { path.line(to: position) }
            // 单点与每个分段起点也可见，不用假造第二个点来画线。
            if point.startsSegment { NSBezierPath(ovalIn: NSRect(x: position.x - 1.5, y: position.y - 1.5, width: 3, height: 3)).fill() }
        }
        path.stroke()
    }
}

@MainActor enum TodayHistoryPresentation {
    // 阶段五：菜单与悬浮窗改用两行独立标签，保证「采集高」「采集低」同时可见。
    // 保留双行字符串仅供旧调用与断言使用，不再作为界面文本源。
    static func rangeText(_ samples: [MinutePriceSample]) -> String {
        guard let range = SparklineGeometry.extremes(samples) else { return "采集高 —\n采集低 —" }
        return String(format: "采集高 %.2f\n采集低 %.2f", range.high, range.low)
    }
    static func highText(_ samples: [MinutePriceSample]) -> String {
        guard let range = SparklineGeometry.extremes(samples) else { return "采集高 —" }
        return String(format: "采集高 %.2f", range.high)
    }
    static func lowText(_ samples: [MinutePriceSample]) -> String {
        guard let range = SparklineGeometry.extremes(samples) else { return "采集低 —" }
        return String(format: "采集低 %.2f", range.low)
    }
    // 问号悬停/点击显示的完整口径；菜单、悬浮窗与说明文档共用同一份文字。
    static let rangeExplanation =
        "采集高 / 采集低的具体口径\n\n" +
        "采集高：本机今天（北京时间 00:00 起）实际采到的所有分钟报价中的最高值。\n" +
        "采集低：同一批报价中的最低值。\n\n" +
        "同一分钟内多次刷新，也会记下这分钟里出现过的最高价和最低价；只统计本应用正在运行、联网且来源报价有效时采到的价格。\n\n" +
        "不包含启动前、断网、休眠或未运行的时段，也不是交易所完整当日最高/最低。跨北京时间零点自动清空，从当天第一个有效报价重新开始。\n\n" +
        "预警规则里的「创新高 / 创新低」也以这个基准判断。"
    static func premiumTooltip(_ premium: DomesticPremium?) -> String {
        guard let premium = premium else { return DomesticPremium.explanation + " 当前汇率或金价缺失/延迟，暂不显示溢价。" }
        return DomesticPremium.explanation + String(format: " 汇率 %.4f，来源 %@ 北京时间。", premium.yuanPerDollar, DisplayFormatters.sourceText(premium.rateSourceAt))
    }
}

// 两行各自是独立标签，避免菜单自定义视图把第二行裁掉；右侧小问号给出口径。
@MainActor final class TodayRangeView: NSView {
    private let highLabel = NSTextField(labelWithString: "采集高 —")
    private let lowLabel = NSTextField(labelWithString: "采集低 —")
    private let help = NSButton()
    private var explanationPopover: NSPopover?
    override init(frame: NSRect) {
        super.init(frame: frame)
        for field in [highLabel, lowLabel] {
            field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            field.textColor = .secondaryLabelColor
            field.alignment = .right
            field.lineBreakMode = .byClipping
            field.maximumNumberOfLines = 1
            addSubview(field)
        }
        help.title = "?"
        help.font = .systemFont(ofSize: 10, weight: .semibold)
        help.isBordered = false
        help.contentTintColor = .tertiaryLabelColor
        help.toolTip = TodayHistoryPresentation.rangeExplanation
        help.target = self
        help.action = #selector(toggleExplanation)
        help.setAccessibilityLabel("查看采集高与采集低的口径")
        addSubview(help)
        setAccessibilityLabel("今日采集高低")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let helpWidth: CGFloat = 14
        help.frame = NSRect(x: bounds.width - helpWidth, y: (bounds.height - 14) / 2, width: helpWidth, height: 14)
        let textWidth = max(40, bounds.width - helpWidth - 4)
        let lineHeight = bounds.height / 2
        highLabel.frame = NSRect(x: 0, y: lineHeight, width: textWidth, height: lineHeight)
        lowLabel.frame = NSRect(x: 0, y: 0, width: textWidth, height: lineHeight)
    }
    func update(samples: [MinutePriceSample]) {
        highLabel.stringValue = TodayHistoryPresentation.highText(samples)
        lowLabel.stringValue = TodayHistoryPresentation.lowText(samples)
        setAccessibilityLabel("\(highLabel.stringValue)，\(lowLabel.stringValue)")
    }
    // 菜单跟踪期间系统 tooltip 可能被抑制，点击问号也能看到同一份说明。
    @objc private func toggleExplanation() {
        if let popover = explanationPopover, popover.isShown { popover.close(); explanationPopover = nil; return }
        let controller = NSViewController()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 204))
        let text = NSTextField(wrappingLabelWithString: TodayHistoryPresentation.rangeExplanation)
        text.font = .systemFont(ofSize: 11)
        text.textColor = .labelColor
        text.frame = NSRect(x: 14, y: 10, width: 312, height: 184)
        host.addSubview(text); controller.view = host
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: help.bounds, of: help, preferredEdge: .minY)
        explanationPopover = popover
    }
}
