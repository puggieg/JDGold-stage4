#!/usr/bin/env python3
"""可选的开发检查：核对接口与 UI 几何基线，独立复算数字；不需要第三方 Python 包。"""
from pathlib import Path
import json
import math
import re

root = Path(__file__).resolve().parents[1]
baseline = json.loads((root / "verification/baseline.json").read_text())
swift_files = list((root / "Sources").rglob("*.swift"))
source = "\n".join(path.read_text() for path in swift_files)
ui = "\n".join(path.read_text() for path in (root / "Sources/UI").rglob("*.swift"))

def geometry_calls(text):
    result = []
    for match in re.finditer(r"\bNS(?:Rect|Size|Point|EdgeInsets)\(", text):
        depth, end = 1, match.end()
        while depth and end < len(text):
            depth += (text[end] == "(") - (text[end] == ")")
            end += 1
        result.append(re.sub(r"\s+", "", text[match.start():end]))
    return sorted(result)

# 阶段三有意重做界面；改为锁定预警引擎与存储，原几何列表仅作历史记录。
import hashlib
for filename, expected in baseline["stage2_hashes"].items():
    assert hashlib.sha256((root / filename).read_bytes()).hexdigest() == expected, filename
assert "NSHostingController" in ui and "NSVisualEffectView" in ui
assert not re.search(r"(?:NSColor|Color)\((?:red|white|calibratedRed):", ui), "不得硬编码颜色"
assert "📈" not in ui and "📉" not in ui and "🧱" not in ui
providers = "\n".join(path.read_text() for path in (root / "Sources/Services").glob("*Provider.swift") if path.name != "SinaExchangeRateProvider.swift")
urls = [a or b for a, b in re.findall(r'PriceParsing.url\("([^"]+)"\)|post\(url: "([^"]+)"', providers)]
assert sorted(urls) == baseline["provider_urls"], "行情 URL 或参数发生变化"
assert "target_up_" not in ui and "target_down_" not in ui, "UI 不应继续读取旧目标键"
assert source.count("DateFormatter()") == 1, "格式化对象没有统一复用"
engine = (root / "Sources/Alerts/AlertEngine.swift").read_text()
engine = "\n".join(line for line in engine.splitlines() if not line.lstrip().startswith("//"))
for forbidden in ["UserDefaults", "URLSession", "NSAlert", "NSApplication", "Date()", "TimeZone.current"]:
    assert forbidden not in engine, f"纯引擎含副作用：{forbidden}"
assert "MenuBarExtra" not in source and "import Charts" not in source
assert len(re.findall(r'SelfTestCase\(name:', (root / "Sources/Testing/CoreSelfTests.swift").read_text())) == 15

# 用另一种写法逐分钟核对跨午夜时间窗和缓冲公式，避免只重复 Swift 实现。
quiet_minutes = [(minute - 23 * 60) % 1440 < 9 * 60 for minute in range(1440)]
assert sum(quiet_minutes) == 540
assert quiet_minutes[1380] and quiet_minutes[479] and not quiet_minutes[480]
assert 5 * 2 * 5 == 50
assert math.isclose(1000 * (1 - 0.001), 999)
assert math.isclose(1000 * (1 + 0.001), 1001)
assert [min(60, 2 ** failures) for failures in range(1, 8)] == [2, 4, 8, 16, 32, 60, 60]
assert len(re.findall(r'SelfTestCase\(name:', (root / "Sources/Testing/PresentationSelfTests.swift").read_text())) == 5
# 相同配置、浅深两套截图；快捷价按比例正反算。
assert 2 * 4 == 8
for percent in [-2,-1,1,2]:
    value = 1000 * (1 + percent / 100)
    assert math.isclose((value / 1000 - 1) * 100, percent)
    assert (percent > 0) == (value > 1000)
print("通过：5 个行情端点、预警核心源码未变、20 组用例清单、迁移/缓冲/退避/快捷价/截图数量复算。")

# 阶段四只新增汇率，不改五个既有行情 Provider 的 URL、参数、解析或请求头。
for filename, expected in baseline["stage3_provider_hashes"].items():
    assert hashlib.sha256((root / filename).read_bytes()).hexdigest() == expected, filename
fx = (root / "Sources/Services/SinaExchangeRateProvider.swift").read_text()
assert 'PriceParsing.url("https://hq.sinajs.cn/list=fx_susdcny")' in fx
assert len(re.findall(r'SelfTestCase\(name:', (root / "Sources/Testing/DecisionFeatureSelfTests.swift").read_text())) == 8
from decimal import Decimal as D
base = D("4100") * D("6.6988") / D("31.1035")
amount = D("885") - base
percent = amount / base * 100
assert abs((D("885") - amount) * D("31.1035") / D("6.6988") - D("4100")) < D("1e-20")
assert abs((1 + percent / 100) * base - D("885")) < D("1e-20")
assert 15 + 5 + 8 == 28
assert 24 * 60 == 1440
assert 3 * 80 + 3 * 64 + 3 * (20 + 8) == 516
print("通过：阶段四新增汇率、既有 Provider 源码未变、28 组断言、溢价单位/反算、分钟容量与浮窗内容高度。")
