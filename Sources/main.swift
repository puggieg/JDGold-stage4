#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Foundation
#if os(macOS)
import Cocoa
#endif

// 显式声明主线程入口；编译参数同时使用 -parse-as-library。
@main
struct JDGoldEntry {
    @MainActor
    static func main() {
        // 自测不创建界面、真实偏好或钥匙串服务。
        if CommandLine.arguments.contains("--selftest") {
            exit(CoreSelfTests.runAll() == 0 ? 0 : 1)
        }
        #if os(macOS)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // 保持代理对象存活，直到应用退出。
        withExtendedLifetime(delegate) { app.run() }
        #else
        fputs("界面需要 macOS；可用 --selftest 验证核心。\n", stderr)
        exit(2)
        #endif
    }
}
