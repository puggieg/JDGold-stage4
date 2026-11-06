#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa

@MainActor final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let panel: FloatingWindow
    private let content: FloatingContentView
    private var fitting = false
    private var configuredMini: Bool?
    private var screenObserver: NSObjectProtocol?
    init(model: SettingsModel) {
        self.model = model
        panel = FloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 624), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        content = FloatingContentView(frame: NSRect(x: 0, y: 0, width: 384, height: 624))
        super.init()
        panel.contentView = content; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self
        content.onPin = { [weak self] in guard let self = self else { return }; self.model.floatingPinned.toggle() }
        content.onClose = { [weak self] in self?.model.floatingVisible = false }
        content.contextMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        restoreFrame(); applySettings()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fitFrame() }
        }
    }
    func applySettings() {
        if configuredMini != model.floatingMini {
            configuredMini = model.floatingMini
            let old = panel.frame; let height: CGFloat = model.floatingMini ? 144 : 624
            panel.setFrame(NSRect(x: old.minX, y: old.maxY - height, width: 384, height: height), display: true)
            fitFrame()
        }
        content.configure(mini: model.floatingMini, selected: model.floatingInstrument, pinned: model.floatingPinned)
        panel.alphaValue = CGFloat(model.floatingOpacity); panel.ignoresMouseEvents = model.mousePassthrough
        panel.isMovableByWindowBackground = !model.floatingPinned
        if model.floatingVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
    func update(prices: GoldPrices, rate: ExchangeRate?, history: TodayPriceHistory, now: Date) { content.update(prices: prices, rate: rate, history: history, now: now) }
    private func rect(_ frame: PanelFrame) -> NSRect { NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
    private func value(_ rect: NSRect) -> PanelFrame { PanelFrame(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
    private func screenID(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "") }
    private func restoreFrame() {
        if let raw = model.defaults.data(forKey: "floatingFrameJSON"), let saved = try? JSONDecoder().decode(PanelFrame.self, from: raw), saved.valid { panel.setFrame(rect(saved), display: false) }
        else if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - 640)) }
        fitFrame()
    }
    private func fitFrame() {
        guard !fitting else { return }; fitting = true; defer { fitting = false }
        let screens = NSScreen.screens.map { PanelScreen(id: screenID($0), frame: value($0.visibleFrame)) }
        let fitted = FloatingGeometry.fit(value(panel.frame), preferredID: model.defaults.string(forKey: "floatingScreenID"), screens: screens)
        panel.setFrame(rect(fitted), display: true); saveFrame()
    }
    func saveFrame() {
        do { model.defaults.set(try JSONEncoder().encode(value(panel.frame)), forKey: "floatingFrameJSON") }
        catch { appLog("悬浮窗", "位置保存失败：\(error)") }
        if let screen = panel.screen { model.defaults.set(screenID(screen), forKey: "floatingScreenID") }
    }
    func windowDidMove(_ notification: Notification) { if !fitting { saveFrame() } }
    func windowDidResize(_ notification: Notification) { if !fitting { saveFrame() } }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        add(menu, title: model.floatingVisible ? "隐藏悬浮窗" : "显示悬浮窗", action: #selector(toggleVisible), key: "f")
        add(menu, title: "完整模式", action: #selector(setFull), on: !model.floatingMini)
        add(menu, title: "迷你模式", action: #selector(setMini), on: model.floatingMini)
        let instruments = NSMenu(); instruments.autoenablesItems = false
        for instrument in Instrument.allCases {
            let item = add(instruments, title: instrument.displayName, action: #selector(setInstrument(_:)), on: model.floatingInstrument == instrument)
            item.representedObject = instrument
        }
        let select = NSMenuItem(title: "迷你模式品种", action: nil, keyEquivalent: ""); select.submenu = instruments; menu.addItem(select)
        let opacity = NSMenu(); opacity.autoenablesItems = false
        for percent in [100,85,70] { let item = add(opacity, title: "\(percent)%", action: #selector(setOpacity(_:)), on: abs(model.floatingOpacity * 100 - Double(percent)) < 0.5); item.tag = percent }
        let transparency = NSMenuItem(title: "透明度", action: nil, keyEquivalent: ""); transparency.submenu = opacity; menu.addItem(transparency)
        menu.addItem(.separator())
        add(menu, title: "固定位置", action: #selector(togglePin), on: model.floatingPinned)
        add(menu, title: "鼠标穿透", action: #selector(togglePassthrough), on: model.mousePassthrough)
        return menu
    }
    @discardableResult private func add(_ menu: NSMenu, title: String, action: Selector, key: String = "", on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; item.state = on ? .on : .off
        menu.addItem(item); return item
    }
    @objc private func toggleVisible() { model.floatingVisible.toggle() }
    @objc private func setFull() { model.floatingMini = false }
    @objc private func setMini() { model.floatingMini = true }
    @objc private func setInstrument(_ sender: NSMenuItem) { if let instrument = sender.representedObject as? Instrument { model.floatingInstrument = instrument } }
    @objc private func setOpacity(_ sender: NSMenuItem) { model.floatingOpacity = Double(sender.tag) / 100 }
    @objc private func togglePin() { model.floatingPinned.toggle() }
    @objc private func togglePassthrough() { model.mousePassthrough.toggle() }
}
