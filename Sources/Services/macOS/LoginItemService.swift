import Cocoa
import ServiceManagement

@MainActor enum LoginItemService {
    static func refresh(_ model: SettingsModel) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { model.loginStatus = "请从 JDGold.app 启动后设置登录项。"; model.loginEnabled = false; return }
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: model.loginEnabled = true; model.loginStatus = "已启用"
            case .requiresApproval: model.loginEnabled = false; model.loginStatus = "请在系统设置中允许登录项。"
            case .notFound: model.loginEnabled = false; model.loginStatus = "登录项未找到，请检查应用是否放在应用程序中。"
            case .notRegistered: model.loginEnabled = false; model.loginStatus = "尚未启用"
            @unknown default: model.loginEnabled = false; model.loginStatus = "请在系统设置中检查登录项。"
            }
        } else { model.loginStatus = "macOS 12 使用系统偏好设置手动添加。" }
    }
    static func setEnabled(_ enabled: Bool, model: SettingsModel) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { refresh(model); return }
        if #available(macOS 13.0, *) {
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refresh(model) }
            catch { refresh(model); model.loginStatus = "更改失败：\(error.localizedDescription)"; appLog("开机启动", error.localizedDescription) }
        }
    }
    static func openSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users") { NSWorkspace.shared.open(url) }
    }
}
