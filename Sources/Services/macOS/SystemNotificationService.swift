import Cocoa
import UserNotifications

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
}
@MainActor final class SystemNotificationService {
    private let delegate = NotificationDelegate()
    private var center: UNUserNotificationCenter? {
        // 直接运行 Unix 文件时不初始化通知中心，防止缺失 Bundle 身份导致异常。
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
    func refreshStatus(_ model: SettingsModel) {
        guard let center = center else { model.notificationStatus = "请从 JDGold.app 启动以使用系统通知。"; return }
        center.delegate = delegate
        center.getNotificationSettings { settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = settings.alertSetting == .enabled ? "系统通知已授权" : "已授权，横幅被系统关闭；将使用浮层"
            case .denied: status = "系统通知未授权，将使用浮层"
            case .notDetermined: status = "尚未请求授权，将使用浮层"
            @unknown default: status = "通知状态未知，将使用浮层"
            }
            Task { @MainActor in model.notificationStatus = status }
        }
    }
    func requestPermission(_ model: SettingsModel) {
        guard let center = center else { refreshStatus(model); return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error = error { appLog("系统通知", "授权失败，错误代码 \((error as NSError).code)") }
            Task { @MainActor [weak self] in self?.refreshStatus(model) }
        }
    }
    func deliver(title: String, body: String, preferSystem: Bool, sound: Bool, fallback: @escaping @MainActor () -> Void) {
        guard preferSystem, let center = center else { fallback(); return }
        center.delegate = delegate
        center.getNotificationSettings { [weak self] settings in
            let allowed = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) && settings.alertSetting == .enabled
            Task { @MainActor [weak self] in
                guard allowed, let center = self?.center else { fallback(); return }
                let content = UNMutableNotificationContent(); content.title = title; content.body = body
                if sound { content.sound = .default }
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request) { error in
                    if let error = error {
                        appLog("系统通知", "发送失败，错误代码 \((error as NSError).code)")
                        Task { @MainActor in fallback() }
                    }
                }
            }
        }
    }
}
