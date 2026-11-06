# JDGold · 阶段四：国内溢价与当日迷你走势

在本次修正版阶段三上新增两项决策功能：比较国内积存金与国际折算价，查看本机采集到的当天走势。阶段三的菜单可选值编译修正已包含。
保持 macOS 12 最低运行目标、Swift Package Manager、build.sh、AppKit 菜单/悬浮窗与 SwiftUI 设置；没有第三方依赖。

**验证范围：28/28 组共享核心断言通过，核心严格并发类型检查及全部 Swift 语法解析通过；当前环境没有 macOS SDK，完整 Mac 编译、签名和界面验收仍需在你的 Mac 完成。**

基于 [PiaoyangGuohai1/GoldPrice（JDGold）](https://github.com/PiaoyangGuohai1/GoldPrice) 二次开发，保留上游署名。上传工程未包含原 LICENSE，保留方式见 [NOTICE.md](NOTICE.md)。

## 怎么生成 App 或 Unix 文件

解压后在终端输入 `cd `，把 **JDGold-stage4 文件夹**拖进去，按回车。先退出旧 JDGold，再执行：

```bash
chmod +x build.sh
./build.sh && open ./JDGold.app
```

脚本先编译、运行核心自测，再在**工程目录**生成新 App；失败时不输出新产物，不直接替换应用程序中的旧版。
优先复制你已有的 JDGold 外壳，保留 Bundle ID、图标、Info.plist 版本和原资源，以便延续旧偏好和钥匙串。原外壳在其他位置时：

```bash
./build.sh --app-shell "/你的实际路径/JDGold.app"
```

确认旧规则、Bark、溢价和走势正常后，退出新 App，再将它拖入应用程序替换；保留旧 App 副本便于回退。
没有完整 Xcode 也能构建，需要 CLT 的 Swift 5.7+ 与包含 SMAppService 的 macOS 13+ SDK，最低运行系统仍为 macOS 12。缺工具时执行 `xcode-select --install`。

只要可替换的 Unix 可执行文件：

```bash
./build.sh --binary-only
./JDGold --selftest
```

工程根目录的 **JDGold** 就是产物，不能只编译 main.swift。退出旧 App 后，将其拖入原 App 的 `Contents/MacOS/`，替换同名文件，再执行：

```bash
codesign --force --deep --sign - "/Applications/JDGold.app"
codesign --verify --deep --strict "/Applications/JDGold.app"
open "/Applications/JDGold.app"
```

## 改了什么、为什么

| 来源 | 功能 |
| --- | --- |
| 上游公开功能 | 三家银行积存金、伦敦金/纽约金、菜单栏、悬浮窗、可选刷新间隔、涨红跌绿 |
| 上传基线与阶段一/二/三已有 | 美元指数、多档预警、自动追踪、Bark；稳定性修复、免打扰、JSON/钥匙串迁移、纯预警引擎、原生界面与 SwiftUI 设置 |
| 本项目阶段四新增 | USD/CNY 汇率、国内溢价及缺失降级、逐分钟本地采样、手绘迷你走势与采集高低、小屏滚动、正常退出补写及对应测试 |

原行情 Provider、AlertEngine 和 AlertStore 保持原样。没有改动原五个行情接口及参数；仅新增一个经真实 curl 核对的汇率 GET 端点。

### 国内溢价

对三家银行分别计算：

`国际折算价（元/克）= 伦敦金（美元/盎司）× USD/CNY ÷ 31.1035`

`溢价（元/克）= 国内积存金价 − 国际折算价`

`溢价百分比 = 溢价 ÷ 国际折算价 × 100`

显示格式：`溢价 +X.XX 元/克（+Y.Y%）`，负溢价按负号显示；菜单与完整悬浮窗均显示，迷你模式选择国内品种时也显示溢价。
悬停说明其含义、未计交易费用及当前采用汇率的来源时间。这一参考差额有助于理解相对贵便宜，不是可直接套利的利润。

汇率取新浪在岸 USD/CNY 当前价。新接口真实响应和字段核对见 [verification/FX_API.md](verification/FX_API.md)。
汇率失败、过期、明显未来时间或无效数字时隐藏溢价；国内价或伦敦金缺失/过期也隐藏。不会用 0、USD/CNH、昨收或失败缓存拼出错误数字。
金价与汇率均按各自来源时间核查，仍可能存在不同步，tooltip 保留汇率时间。

### 当日迷你走势

- **北京时间分日**，与中国市场和现有来源时间展示保持一致；跨日立即隐藏旧线并自动清空本地当天文件。
- 每品种每分钟最多一条：保留分钟内最新采集价，并同时保存该分钟高低价，避免高频刷新造成文件膨胀或遗漏已观察的高低。
- 菜单中每品种都有迷你线；完整悬浮窗各行显示线和“采集高/低”。图用 **NSBezierPath** 绘制，不使用 Swift Charts；迷你模式保持简洁，不显示走势。
- 平盘画水平线，只有一个样本画一个点；无样本显示“今日暂无采样”，高低显示 `—`。断网后保留已采集线并变灰；不会把失败缓存采成新的点。缺口超过相邻两个分钟桶时断线，不连成连续行情。
- “采集高/低”包含分钟内已观察价格，**不包含启动前、断网或休眠期间**，不是交易所完整当日最高/最低。数据源时间过期时跳过新采样。
- 数据保存在 `~/Library/Application Support/<原 Bundle ID>/today-prices.json`；不改规则 UserDefaults。常规每分钟至多写盘一次，下一分钟带上上一分钟最终数据；正常退出异步补写，最多等两秒。强制结束或保存失败可能缺最后一分钟的采样。
- 同日重开恢复样本；损坏文件移到同目录备份后从空记录开始，备份失败则暂停写盘保留原件。写盘失败仍显示内存采样，并输出统一日志。
- 完整悬浮窗采用滚动内容区域，小屏或显示器断开后仍可查看全部品种；保留固定、关闭、鼠标穿透和位置恢复。

## 新代码阅读入口

| 文件 | 职责 |
| --- | --- |
| `Models/DomesticPremium.swift` | 单位、时效检查及纯溢价计算 |
| `Services/SinaExchangeRateProvider.swift` | 真实响应解析与汇率获取/退避，复用 HTTPClient、RetryPolicy |
| `Models/TodayPriceHistory.swift` | 北京时间分日、分钟合并、采集高低与纯走势坐标 |
| `Services/TodayHistoryStore.swift` | actor 管理 JSON 文件、恢复、清空、原子写入及退出补写 |
| `UI/TodaySparklineView.swift` | NSBezierPath 手绘与无样本状态 |
| `Testing/DecisionFeatureSelfTests.swift` | 新增八组边界断言，与 --selftest / XCTest 共用 |

阶段三菜单 `NSMenuItem?` 已安全解包。旧 JSON、五十键迁移、autoStep、Bark 钥匙串和状态栏设置继续兼容，预警算法没有变化。
本阶段不包含可选 CSV 导出，先完成这两项的 Mac 实机验收。

## 我该怎么手动验证

1. **先构建**：运行 `./build.sh`，应看到 `28/28 项通过` 后生成 App。打开新 App 核对旧规则、Bark、状态栏品种、刷新间隔，并退出重开检查。
2. **溢价**：网络正常且三项来源都及时有效时，三家国内报价下显示溢价；对照伦敦金与 tooltip 中的汇率，用公式手算一行。迷你模式选择国内品种也应显示；国际品种不显示国内溢价。
3. **采样**：完整悬浮窗和菜单先显示点，再等跨过下一分钟应有线和采集高低。频繁手动刷新不会增加同分钟记录数。这里的高低只覆盖本机实际采到的报价。
4. **降级**：断网后立即刷新，应保留旧价、走势变灰，溢价隐藏；恢复后等待失败退避到期，有效来源恢复则再显示。任意来源已延迟时该行溢价可能继续隐藏，这是有效性保护。
5. **重启与跨日**：从菜单正常退出、同日重开，走势应恢复；跨北京时间午夜后昨日线和高低清空，随后从新日第一点开始。无需改系统时间，跨日逻辑也有固定输入测试覆盖。
6. **布局**：浅色、深色各检查一次；完整/迷你切换；在小屏或第二显示器断开后，完整模式可滚动查看最后一行，固定/关闭/穿透恢复仍有效。
7. **故障边界**：汇率无效、缺失/过期、存储损坏、分钟去重、缺口和极值用共享自测验证，不需要破坏你的真实数据来测试。

自动复核：

```bash
./verification/verify-macos.sh
# XCTest runner 可用时：
./verification/verify-macos.sh --xctest
# 可选 Python 检查：
python3 verification/verify_source.py
python3 verification/build-script-tests.py
```

实际测试范围与平台限制见 [verification/RESULTS.md](verification/RESULTS.md)。Mac 编译或界面出现问题时，保留完整终端错误便于定位；不要把核心通过等同于完整 App 已验收。

## 作品集截图

浅色、深色仍各四张：菜单栏＋展开菜单、完整悬浮窗、预警规则页、通知页。
阶段四前两张重点展示真实的溢价、分钟走势、采集高低和来源时间；不要把无效来源时隐藏的指标用截图编辑补上。Bark Key 必须隐藏。
阶段三详细设计记录保留在 [docs/STAGE3.md](docs/STAGE3.md)。

行情与预警仅供参考，不构成投资建议；交易以银行或平台实际价格为准。
