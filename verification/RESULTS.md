# 阶段四验证记录

基线：修正可选菜单项编译错误后的阶段三。日期：2026-10-14。
环境：Linux，官方 Swift 6.1.3 frontend，Swift 5 语言模式；无 macOS SDK。

## 已实际执行

| 检查 | 结果与实际范围 |
| --- | --- |
| 共享核心断言 | 官方 frontend -emit-object -O 编译，GCC 链接官方 Swift/Foundation 运行时，直接调用 CoreSelfTests.runAll；28/28 通过，包含原二十组和新增八组 |
| 核心类型检查 | -strict-concurrency=complete -warnings-as-errors，通过 |
| 所有 Swift 源文件 | 官方 frontend -parse，通过；不能替代 macOS SDK 类型检查 |
| 走势视图 | 最小 Cocoa 类型替身下严格类型检查通过，只验证 Swift 类型与调用结构，不验证真实 AppKit 绘制 |
| XCTest 源码 | 带 enable-testing 的核心模块 + XCTest 包装源码类型检查，通过；未运行完整 SwiftPM runner |
| SwiftPM manifest | PackageDescription 5.7 类型检查，通过 |
| 构建脚本 | bash -n，通过；模拟双架构/单架构/失败/自测失败/空格路径/未知参数流程通过，不冒充真实 lipo 与 codesign |
| 旧源码与接口 | Python SHA-256 核对原 Provider、AlertEngine、AlertStore 保持原样，旧接口 URL 与参数未改 |
| 新汇率 | curl 实际返回 18 个字段的 fx_susdcny，查官方网页引用的 sf_sdk.js 核对当前价 8、日期 17、时间 0；见 FX_API.md 和原始响应 |
| 数字复核 | Python Decimal 溢价公式正反算；分钟容量、共享测试数、布局高度复算 |
| 布局几何 | Python 枚举菜单、完整/迷你行矩形，检查数字、溢价、走势和高低不重叠；小屏以滚动保留内容 |

selftest-output.txt 保存实际标准输出。构建模拟输出见 build-script-output.txt。

新增八组：汇率字段/拒绝无效响应；汇率失败/退避/恢复/防重入；溢价单位/正负/反算；缺失/过期/未来/溢出降级；分钟合并与分钟内高低；本地恢复/补写/清空/损坏/写盘失败；北京时间跨日/跨年/容量；走势平盘/单点/缺口/极值。
自测使用隔离目录和假客户端，不请求真实行情，不发送通知/Bark，不读写真实钥匙串或用户规则。

## 待 Mac 验证

完整 AppKit / SwiftUI / Security / UserNotifications / ServiceManagement 编译、真实签名、生产 --selftest 参数分支、实际 NSBezierPath 绘制和滚动/多屏布局、退出补写和系统通知行为均未在本环境验收。
Swift driver 在本环境无法正常启动，测试使用 frontend 与 GCC 绕过；通过 Python 管道捕获实际测试输出。不能将这套 Linux 核心验证声称为完整 Mac 构建通过。

请在 Mac 运行 `./verification/verify-macos.sh`，再 `./build.sh && open ./JDGold.app`，按 README 验收。
CSV 为可选项，本阶段未加入，避免在实机验收前扩大功能范围。
阶段三原验证记录保存在 docs/STAGE3_VERIFICATION.md。
