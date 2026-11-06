#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import SwiftUI
import Cocoa

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
    }
}
@MainActor struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $model.selectedTab) {
                GeneralSettingsView(model: model).tabItem { Label("通用", systemImage: "gearshape") }.tag(0)
                RulesSettingsView(model: model).tabItem { Label("预警规则", systemImage: "bell.badge") }.tag(1)
                NotificationSettingsView(model: model).tabItem { Label("通知", systemImage: "bell") }.tag(2)
                AboutSettingsView(model: model).tabItem { Label("关于", systemImage: "info.circle") }.tag(3)
            }
            if !model.errorMessage.isEmpty { Text(model.errorMessage).foregroundColor(Color(nsColor: .systemRed)).padding(.horizontal, 16) }
        }.padding(16).frame(minWidth: 720, minHeight: 600)
    }
}
@MainActor struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard("行情与菜单栏") {
                    Picker("刷新间隔", selection: $model.refreshInterval) {
                        ForEach([3,5,10,30,60], id: \.self) { Text("\($0) 秒").tag(Double($0)) }
                    }
                    Picker("显示品种", selection: $model.statusInstrument) {
                        ForEach(Instrument.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Toggle("显示涨跌幅", isOn: $model.showMovement)
                    Toggle("涨跌幅着色（涨红、跌绿）", isOn: $model.colorMovement)
                }
                SettingsCard("悬浮窗") {
                    Toggle("显示悬浮窗", isOn: $model.floatingVisible)
                    Toggle("迷你模式", isOn: $model.floatingMini)
                    Picker("迷你模式品种", selection: $model.floatingInstrument) {
                        ForEach(Instrument.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack { Text("透明度"); Slider(value: $model.floatingOpacity, in: 0.5...1); Text("\(Int(model.floatingOpacity * 100))%").monospacedDigit().frame(width: 48) }
                    Toggle("固定位置", isOn: $model.floatingPinned)
                    Toggle("鼠标穿透", isOn: $model.mousePassthrough)
                    Text("开启鼠标穿透后，可在这里或菜单栏的悬浮窗选项中关闭。多显示器断开后，窗口会回到可见区域。")
                        .font(.caption).foregroundColor(.secondary)
                }
                SettingsCard("开机启动") {
                    if #available(macOS 13.0, *) {
                        Toggle("登录后打开 JDGold", isOn: Binding(get: { model.loginEnabled }, set: { model.onLoginChange?($0) }))
                    } else {
                        Text("macOS 12：打开系统偏好设置 → 用户与群组 → 登录项，点击 +，选择应用程序中的 JDGold。")
                    }
                    Text(model.loginStatus).font(.caption).foregroundColor(.secondary)
                    Button("打开登录项设置") { LoginItemService.openSettings() }
                }
            }.padding(16)
        }
    }
}
@MainActor struct AboutSettingsView: View {
    @ObservedObject var model: SettingsModel
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "版本信息未提供" }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 48)).foregroundColor(.secondary)
                Text("JDGold").font(.largeTitle)
                Text(version).foregroundColor(.secondary)
                SettingsCard("开源出处") {
                    Text("基于 PiaoyangGuohai1/GoldPrice（JDGold）二次开发，保留上游作者署名。")
                    Link("查看上游开源项目", destination: URL(string: "https://github.com/PiaoyangGuohai1/GoldPrice")!)
                    Text("上游：行情、菜单栏、悬浮窗、多档预警、自动追踪、Bark。\n本项目：稳定性修复、可测试预警引擎、规则管理、钥匙串及原生界面重设计。")
                        .font(.callout).foregroundColor(.secondary)
                    if !UPDATE_REPO.isEmpty { Button("检查更新") { model.onCheckUpdate?() } }
                }
                SettingsCard("免责声明") {
                    Text("行情可能延迟或不可用。预警仅供信息参考，不构成投资建议；交易价格以银行或交易平台为准。Mac 休眠、断网、系统通知设置及手机权限都可能影响提醒。")
                        .foregroundColor(.secondary)
                }
            }.padding(16)
        }
    }
}
