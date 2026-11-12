import Cocoa

// 非激活面板默认不接受键盘事件；这里允许成为 key window，回车才有落点。
@MainActor private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AlertWindowController: NSObject {
    private var windows: [NSPanel] = []
    private var keyMonitor: Any?

    func showAlert(title: String, body: String, sound: Bool) {
        let window = AlertPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 192),
                                styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = title; window.level = .floating; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 384, height: 192))
        view.material = .popover; view.state = .active
        let icon = NSImageView(frame: NSRect(x: 16, y: 132, width: 32, height: 32))
        icon.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "预警"); view.addSubview(icon)
        let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.frame = NSRect(x: 64, y: 136, width: 304, height: 24); view.addSubview(heading)
        let label = NSTextField(wrappingLabelWithString: body); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
        // 首行是触发时的本地时间戳，比原来的正文多一行；完整正文仍可用悬停查看。
        label.frame = NSRect(x: 16, y: 50, width: 352, height: 78); label.maximumNumberOfLines = 6; label.toolTip = body; view.addSubview(label)
        let button = NSButton(title: "知道了", target: self, action: #selector(dismiss(_:)))
        button.bezelStyle = .rounded
        // 回车即默认按钮；本地监听会先截获按键，二者不会同时关掉两个窗口。
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 280, y: 16, width: 88, height: 32); view.addSubview(button)
        window.contentView = view
        window.defaultButtonCell = button.cell as? NSButtonCell
        installKeyMonitor()
        windows.removeAll { !$0.isVisible }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maximum = max(1, min(3, Int(visible.height / 224)))
        while windows.count >= maximum { windows.removeFirst().close() }
        windows.append(window)
        restack()
        window.makeKeyAndOrderFront(nil)
        // 让配件型应用接收键盘事件；不弹出 Dock 图标，也不改变窗口层级。
        NSApp.activate(ignoringOtherApps: true)
        if sound { NSSound.beep() }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 36 || event.keyCode == 76 else { return event }
            // 只在提醒窗口是 key window 时截获，避免抢走设置窗口里的回车。
            guard let key = NSApp.keyWindow, key is AlertPanel else { return event }
            Task { @MainActor [weak self] in self?.closeOne() }
            return nil
        }
    }

    // 一次回车只关一个窗口；关完把剩余窗口重排，并让下一个成为 key window。
    private func closeOne() {
        guard let target = (NSApp.keyWindow as? NSPanel).flatMap({ key in windows.first { $0 === key && $0.isVisible } })
                ?? windows.last(where: { $0.isVisible }) else { return }
        close(target)
    }
    private func close(_ window: NSPanel) {
        window.close()
        windows.removeAll { !$0.isVisible }
        restack()
        windows.last?.makeKeyAndOrderFront(nil)
    }
    private func restack() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        for (index, panel) in windows.enumerated() {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 400, y: visible.maxY - 208 - CGFloat(index) * 208))
        }
    }
    @objc private func dismiss(_ sender: NSButton) {
        if let window = sender.window as? NSPanel { close(window) }
    }
}
