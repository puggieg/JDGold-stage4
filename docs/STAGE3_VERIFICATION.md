# 阶段三验证记录

验证基线：本次上传 `JDGold-stage2.zip`。日期：2026-10-14。
环境：Linux；官方 Swift 6.1.3 frontend，Swift 5 语言模式；没有 macOS SDK。

## 已实际执行

| 检查 | 结果及实际范围 |
| --- | --- |
| 核心类型检查 | Swift frontend `-typecheck -strict-concurrency=complete -warnings-as-errors`，通过 |
| 共享核心断言 | frontend `-emit-object -O` 实际编译，GCC 链接官方 Swift/Foundation 运行时，独立测试入口直接调用 `CoreSelfTests.runAll()`；20/20 通过 |
| 所有 Swift 语法 | 官方 frontend `-parse`，通过；不等于 macOS 框架类型检查 |
| SettingsModel | 最小 Cocoa/SwiftUI 类型替身下严格并发类型检查通过；只验证模型与回调，不验证真实框架行为 |
| XCTest 源码 | 编译带 enable-testing 的核心模块后类型检查 XCTest 包装源码，通过；没有运行 SwiftPM XCTest runner |
| SwiftPM manifest | PackageDescription 5.7 类型检查，通过；没有完整 Mac SwiftPM 构建 |
| Bash | `bash -n` 与 `--help` 通过；Bash 变量加花括号，数组保留空格路径 |
| 构建模拟 | 假 macOS 工具检查双架构、单架构、都失败、自测失败、未知参数；成功输出，失败保留原二进制。不是实际 Swift 编译/lipo/codesign |
| 接口/核心基线 | Python 核对五个行情 URL、预警引擎及存储源码 SHA-256 未变；独立复算五十键、缓冲/退避/快捷价/截图数量 |
| 真实行情 curl | 三家银行及新浪公开响应保存在 fixtures，来源时间 Python 转换并反算核对；美元指数响应为空，未添加时间字段 |

实际自测输出见 `selftest-output.txt`。引擎覆盖原十五组场景，新增五组展示/交互断言：来源时间、延迟/最低价、规则草稿、Bark 链接、多屏位置。
构建模拟输出见 `build-script-output.txt`。

## 必须在 Mac 上完成

- `./build.sh` 两架构 AppKit / SwiftUI / Security / UserNotifications / ServiceManagement 的真实编译与本地签名。
- 生产 App 的 `--selftest` 参数分支、完整 SwiftPM 构建与可选 XCTest runner。
- macOS 12 的运行验收及 macOS 13+ 的登录项注册。
- 浅深色布局、屏幕缩放、辅助功能、键盘快捷键、价格闪烁、真实多屏拖动/拔插。
- 旧偏好和钥匙串的实机迁移、通知授权/横幅/浮层、真实 Bark 手机送达。

本环境 Swift driver 出现 Signal 4；使用官方 frontend 绕过 driver 验证共享核心。生产入口虽然可在 Linux 编译，但独立链接方式没有完成命令行参数分支的有效运行，故不将它计作 `--selftest` 已验收。
这些平台限制不能通过模拟类型替身或语法解析消除。无需完整 Xcode，可在 Mac 用 CLT 运行下列命令：

```bash
./verification/verify-macos.sh
./build.sh
open ./JDGold.app
```

需要 Swift 5.7+ 且 SDK 包含 macOS 13 的 SMAppService；最低运行目标仍是 macOS 12，13+ API 均放在 availability 分支。

## 原许可证

上传 ZIP 没有原 LICENSE，本次没有改写许可证。构建复用旧外壳保留原资源，根目录有 LICENSE 时原样复制。发布前按 NOTICE 补齐原件。

## 用户实机编译反馈修正

用户在 arm64/x86_64 编译时发现 `StatusBar.swift` 把 `NSMenuItem?` 传给 `NSMenu.addItem`。已改为 `if let` 解包，其他行为不变。
实际检查了修复命令的备份、重复运行和空格路径；Swift 编译反例复现该类型错误，修正例对有值/无值输入通过。所有 Swift 源码语法解析通过。仍不声称已完成完整 macOS 编译。
