#!/usr/bin/env python3
"""用假工具检查 Bash 流程，绝不冒充真实 macOS 编译。测试工程路径包含空格。"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="JDGold build with spaces ") as temporary:
    work = Path(temporary)
    shutil.copy(root / "build.sh", work / "build.sh")
    (work / "Sources").mkdir()
    (work / "Sources" / "main.swift").write_text("// placeholder for mocked compiler\n")
    (work / "tools").mkdir()
    commands = {
        "uname": "#!/bin/bash\necho Darwin\n",
        "codesign": "#!/bin/bash\nexit 0\n",
        "xcrun": '''#!/bin/bash
set -eu
if [ "${1:-}" = --find ]; then echo /mock/swiftc; exit 0; fi
if [ "${1:-}" = --sdk ]; then shift 2; fi
case "${1:-}" in
--show-sdk-path) echo /mock/sdk; exit 0 ;;
lipo) shift; while [ "$#" -gt 0 ]; do if [ "$1" = -output ]; then cp "$first" "$2"; exit 0; fi; if [ "$1" != -create ] && [ -z "${first:-}" ]; then first="$1"; fi; shift; done ;;
swiftc)
 shift; target=""; output=""; parsed=false
 while [ "$#" -gt 0 ]; do
  case "$1" in -target) target="$2"; shift 2;; -o) output="$2"; shift 2;; -parse-as-library) parsed=true; shift;; *) shift;; esac
 done
 "$parsed" || exit 4
 case "$TEST_BUILD_MODE:$target" in both-fail:*|single:x86_64*) exit 5;; esac
 printf '#!/bin/bash\\n[ "$1" = --selftest ] || exit 6\\n[ "${TEST_BUILD_MODE:-}" != selftest-fail ]\\n' > "$output"
 chmod +x "$output" ;;
*) exit 7;;
esac
''',
    }
    for name, text in commands.items():
        path = work / "tools" / name
        path.write_text(text)
        path.chmod(0o755)
    for mode in ["dual", "single", "both-fail", "selftest-fail"]:
        binary = work / "JDGold"
        binary.write_text("old binary unchanged")
        environment = dict(os.environ, PATH=str(work / "tools") + os.pathsep + os.environ["PATH"], TEST_BUILD_MODE=mode, TMPDIR=str(work))
        result = subprocess.run(["bash", str(work / "build.sh"), "--binary-only"], env=environment, capture_output=True, text=True)
        if mode in ["dual", "single"]:
            assert result.returncode == 0, result.stdout + result.stderr
            assert binary.read_text().startswith("#!/bin/bash"), mode
        else:
            assert result.returncode != 0, mode
            assert binary.read_text() == "old binary unchanged", mode
        print("通过：模拟构建", mode)
    result = subprocess.run(["bash", str(work / "build.sh"), "--unknown"], capture_output=True)
    assert result.returncode == 2
    print("通过：未知参数被拒绝")
print("模拟流程检查完成；macOS 编译、lipo 和 codesign 仍须实机验证。")
