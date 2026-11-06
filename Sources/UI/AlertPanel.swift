import Cocoa

@MainActor final class AlertWindowController: NSObject {
    private var windows: [NSPanel] = []
    func showAlert(title: String, body: String, sound: Bool) {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 192),
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
        label.frame = NSRect(x: 16, y: 56, width: 352, height: 72); label.maximumNumberOfLines = 4; label.toolTip = body; view.addSubview(label)
        let button = NSButton(title: "知道了", target: self, action: #selector(dismiss(_:))); button.bezelStyle = .rounded
        button.frame = NSRect(x: 280, y: 16, width: 88, height: 32); view.addSubview(button)
        window.contentView = view
        windows.removeAll { !$0.isVisible }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maximum = max(1, min(3, Int(visible.height / 224)))
        while windows.count >= maximum { windows.removeFirst().close() }
        windows.append(window)
        for (index, panel) in windows.enumerated() { panel.setFrameOrigin(NSPoint(x: visible.maxX - 400, y: visible.maxY - 208 - CGFloat(index) * 208)) }
        window.orderFront(nil)
        if sound { NSSound.beep() }
    }
    @objc private func dismiss(_ sender: NSButton) { sender.window?.close(); windows.removeAll { !$0.isVisible } }
}
