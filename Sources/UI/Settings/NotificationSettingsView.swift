#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Cocoa
import SwiftUI

@MainActor struct NotificationSettingsView: View {
    @ObservedObject var model: SettingsModel
    private var minuteOptions: [Int] { Array(Set(stride(from: 0, to: 1440, by: 15)).union([model.quietStart, model.quietEnd])).sorted() }
    private var preview: BarkLink? { try? BarkLinkParser.parse(model.barkInput) }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard("Mac 通知") {
                    Toggle("优先使用系统通知中心", isOn: $model.systemNotifications)
                    Toggle("播放提示音", isOn: $model.soundEnabled)
                    HStack { Text(model.notificationStatus).foregroundColor(.secondary); Spacer(); Button("请求通知授权") { model.onRequestNotification?() } }
                    Text("未授权或系统通知发送失败时，使用非模态浮层提醒。免打扰期间不弹出、不响铃；结束后汇总一条，并推送到已绑定的 Bark。")
                        .font(.caption).foregroundColor(.secondary)
                }
                SettingsCard("免打扰") {
                    Toggle("启用免打扰时段", isOn: $model.quietEnabled)
                    HStack {
                        Picker("开始", selection: $model.quietStart) { ForEach(minuteOptions, id: \.self) { Text(timeText($0)).tag($0) } }
                        Picker("结束", selection: $model.quietEnd) { ForEach(minuteOptions, id: \.self) { Text(timeText($0)).tag($0) } }
                    }.disabled(!model.quietEnabled)
                    Text("按 Mac 当前时区 \(TimeZone.current.identifier) 执行。开始与结束相同表示不限制时段。")
                        .font(.caption).foregroundColor(.secondary)
                }
                SettingsCard("Bark · 手机推送") {
                    Text("1 · 在 iPhone 安装 Bark").font(.headline)
                    Link("打开 Bark 下载页", destination: URL(string: "https://apps.apple.com/cn/app/id1403753865")!)
                    Divider()
                    Text("2 · 粘贴 Bark 中的推送链接").font(.headline)
                    SecureField("https://api.day.app/你的Key/…?level=critical&call=1", text: $model.barkInput).textFieldStyle(.roundedBorder).disabled(model.barkBusy)
                    if let value = preview {
                        Text("识别到 \(value.maskedKey) · \(value.level == "critical" ? "重要警告" : "普通提醒")\(value.continuousRing ? " · 持续响铃" : "")")
                            .font(.caption).foregroundColor(.secondary)
                    } else if !model.barkInput.isEmpty {
                        Text("链接无法解析，请检查域名、Key 和参数。").font(.caption).foregroundColor(Color(nsColor: .systemRed))
                    }
                    Text("重要警告（level=critical）：手机已授权时，可突破静音和专注模式。\n持续响铃（call=1）：重复播放铃声约 30 秒；两者可组合使用，实际效果受 Bark 版本及手机权限影响。\n本程序发出的所有推送（含测试推送）都会自动归入 Bark 的「Gold Monitor」分组；链接里自带的 group 参数会被覆盖。")
                        .font(.caption).foregroundColor(.secondary)
                    HStack { Button("保存绑定") { model.saveBark() }.disabled(preview == nil || model.barkBusy); Button("解绑") { model.saveBark(unbind: true) }.disabled(model.barkBusy); Spacer(); Text(model.barkStatus).font(.caption).foregroundColor(.secondary) }
                    Divider()
                    Text("3 · 发送测试，确认手机收到").font(.headline)
                    Button("发送测试推送") { model.testBark() }.disabled(model.barkBusy)
                    if model.barkBusy { ProgressView().controlSize(.small) }
                    if !model.barkResult.isEmpty { Text(model.barkResult).font(.callout).textSelection(.enabled) }
                    Text("服务端接受推送不等于手机已收到，请同时查看手机。测试也遵循免打扰。Key 存在钥匙串中，不出现在日志和截图里。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.padding(16)
        }
    }
    private func timeText(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}
