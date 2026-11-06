#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CLT-only 先跑同一套断言；XCTest 作为可选补充，不把 Xcode.app 作为前提。
./build.sh --binary-only
./JDGold --selftest
xcrun swift build -c release
if [ "${1:-}" = --xctest ]; then xcrun swift test; fi
echo '核心自测与 SwiftPM 构建已完成。用 ./build.sh 打包 .app，再按 README 验收浅深色、规则、通知及多屏。'
