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

## 阶段五追加验证（2026-11-06，本机 macOS）

| 检查 | 结果与实际范围 |
| --- | --- |
| 双架构编译与签名 | `./build.sh --binary-only` 编译 arm64 + x86_64、lipo 合并、ad-hoc 签名通过；`./build.sh` 生成完整 `JDGold.app` 并通过 `codesign --verify --deep --strict` |
| 共享核心断言 | `./JDGold --selftest` 37/37 通过，其中 9 项为阶段五新增（首报/冷静期汇总、幅度门槛与慢牛、方向独立、开关重启用、跨日与无效行情、品种范围与纯函数、免打扰路由与状态持久化、本地时间戳与跨日年份、菜单默认银行跟随显示品种） |
| 源码与接口 | `python3 verification/verify_source.py` 通过；原 Provider URL、AlertRule/AlertState/AlertStore 哈希未变，AlertEngine 只新增纯路由入口并更新对应哈希 |
| 构建脚本模拟 | `python3 verification/build-script-tests.py` 5 项模拟流程通过 |
| SwiftPM | `xcrun swift build -c release` 在本会话沙箱中因 `sandbox-exec` 权限失败，属环境限制；同一源码经 build.sh 的 swiftc 路径已编译通过 |

新增九组：新高首报与冷静期汇总；幅度门槛与缓慢单边上涨；新高与新低方向独立；开关关闭与重新启用；跨日重置与无效行情；品种多选与纯函数；免打扰路由与状态持久化；提醒本地时间戳与跨日年份；菜单默认银行跟随显示品种。
自测使用固定时间与内存状态，不请求真实行情、不发送通知、不读写真实规则或钥匙串。

**仍待实机肉眼验收**：问号 tooltip 在菜单跟踪期间的实际表现（已提供点击弹出说明作为兜底）、提醒窗口连按 Enter 的焦点行为、弹窗/Bark 里时间戳的实际显示与跨 0 点年份、浅深色布局与 🧱 字形。展开按钮展开态颜色已于 2026-11-12 截图验证，见下一节。其余按 README 第 8–12 项检查。
设计说明见 [docs/STAGE5.md](../docs/STAGE5.md)。

## 阶段五追加：提醒时间戳与展开按钮配色（2026-11-10）

| 检查 | 结果与实际范围 |
| --- | --- |
| 双架构编译与签名 | `./build.sh` 重新编译 arm64 + x86_64、生成 `JDGold.app` 并通过 `codesign --verify --deep --strict` |
| 共享核心断言 | `./JDGold --selftest` 36/36 通过；新增「提醒本地时间戳与跨日年份」1 组，覆盖 `MM-DD hh:mm:ss` / `YYYY-MM-DD hh:mm:ss`（时分秒半角冒号）、补零、固定时区语义、同日/跨 0 点/重启后的年份判定 |
| 源码与接口 | `python3 verification/verify_source.py` 通过；`AlertEngine`/`AlertState`/`AlertRule`/`AlertStore` 及五个 Provider 哈希均未变 |
| 一致性 | 时间戳统一在 `acceptEngineResult` 加到正文首行，系统通知横幅、应用内浮层与 Bark 拿到同一份文案；Bark 测试推送同样带时间 |

该改动只涉及展示层文案与 `Models/AlertTimeStamp.swift` 纯函数，不改预警判定、规则存储与行情接口。免打扰期间只记日志，不消耗「当天第一条」标记。

## 阶段五追加：默认银行跟随显示品种 + 展开按钮配色重修（2026-11-12）

| 检查 | 结果与实际范围 |
| --- | --- |
| 双架构编译与签名 | `./build.sh` 编译 arm64 + x86_64、生成 `JDGold.app`，`codesign --verify --deep --strict` 通过 |
| 共享核心断言 | `./JDGold --selftest` **37/37** 通过；新增「菜单默认银行跟随显示品种」1 组，覆盖三家银行分别作为默认时的排序/其余两家集合，以及选中国际品种时回退工商银行 |
| 源码与接口 | `verification/verify_source.py`、`build-script-tests.py` 通过；`AlertEngine`/`AlertState`/`AlertRule`/`AlertStore` 与五个 Provider 哈希均未变 |
| **实机截图** | 用仅在 `--debug-expanded` 下生效的临时钩子，在菜单打开前走完点击路径（`setExpanded(true)` → `setLinkText`），截图确认：**「隐藏其余银行金价」为蓝色**；按钮文字区域 200×28 物理像素里蓝色像素 2014 个、非背景杂色仅 124 个，无黑色笔画。同一张图还确认菜单默认显示的是偏好中选中的**民生银行**，展开按钮在它下方，其余两家为工行/浙商 |

上一轮的 `attributedTitle` + `attributedAlternateTitle` + `contentTintColor` 方案在菜单项高亮/焦点态仍被 `NSButtonCell` 接管前景色，实测点击后变黑。本轮改为 `BlueLinkButton` 继承 `NSButton`（保留菜单 hitTest 与点击）但**重写 `draw(_:)` 自绘蓝色文字、不调用 `super.draw`**，颜色不再受任何按钮状态影响；`refusesFirstResponder = true` 去掉焦点环。`setLinkText` 更新文字后强制 `needsDisplay`。`verify_source.py` 已加断言禁止回退到属性字符串方案。

默认银行改为 `MenuBankPresentation.primary(model.statusInstrument)`：三家银行直接跟随，选中国际品种/美元指数时回退工商银行；`SettingsModel.onMenuBankChange` 触发 `setupMenu()` 重建菜单，默认那家、另外两家与展开按钮位置一起变化，并重置单次展开状态。两套显示逻辑（单次展开 / 偏好常显示）保持不变。

临时调试钩子已从 `AppDelegate.swift`、`StatusBar.swift` 移除并重新完整构建，最终产物无残留。

## 阶段五追加：汇总箭头与 Bark 分组（2026-11-12 晚）

| 检查 | 结果与实际范围 |
| --- | --- |
| 双架构编译与签名 | `./build.sh` 通过，`codesign --verify --deep --strict` 通过 |
| 共享核心断言 | `./JDGold --selftest` **37/37** 通过；在现有用例里新增断言，覆盖两个方向汇总标题的箭头、`groupedQuery` 的四种输入（nil/空/原参数/已有 group 覆盖）及解码后分组名 |
| 源码与接口 | `verify_source.py`、`build-script-tests.py` 通过；baseline 里四个预警核心文件与五个 Provider 哈希全部不变 |
| 产物一致性 | 根目录 `JDGold-stage5.app` 与 zip 重新生成，二进制哈希与工程内 App 一致；二进制中确认含 `⤵` 与 `group=Gold%20Monitor` |

改动：`ExtremeAlertEngine` 汇总标题由统一 `⤴` 改为 `high ? "⤴" : "⤵"`；`BarkLinkParser.groupedQuery(_:)` 纯函数剔除已有 `group` 后追加 `group=Gold%20Monitor`，`BarkNotificationService.send` 无条件使用，覆盖预警、汇总、免打扰补发、目标顺延与测试推送；持久化原始链接不改写。`verify_source.py` 加了禁止回退的断言。

**仍待实机验收**：Bark 手机端是否确实把推送显示到「Gold Monitor」分组（服务端接受推送不等于手机已收到并正确分组），以及汇总提醒标题里 `⤴`/`⤵` 在浅深色下的显示，见 README 第 13 项。
