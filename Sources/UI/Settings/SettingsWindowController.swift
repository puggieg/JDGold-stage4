import Cocoa
import SwiftUI

@MainActor final class SettingsWindowController {
    private var window: NSWindow?
    func show(model: SettingsModel, tab: Int = 0) {
        model.selectedTab = tab
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            value.title = "JDGold 偏好设置"; value.isReleasedWhenClosed = false
            value.minSize = NSSize(width: 720, height: 600)
            value.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            value.center(); window = value
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
