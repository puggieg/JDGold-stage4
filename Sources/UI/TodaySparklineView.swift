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
    static func rangeText(_ samples: [MinutePriceSample]) -> String {
        guard let range = SparklineGeometry.extremes(samples) else { return "采集高 —\n采集低 —" }
        return String(format: "采集高 %.2f\n采集低 %.2f", range.high, range.low)
    }
    static func premiumTooltip(_ premium: DomesticPremium?) -> String {
        guard let premium = premium else { return DomesticPremium.explanation + " 当前汇率或金价缺失/延迟，暂不显示溢价。" }
        return DomesticPremium.explanation + String(format: " 汇率 %.4f，来源 %@ 北京时间。", premium.yuanPerDollar, DisplayFormatters.sourceText(premium.rateSourceAt))
    }
}
