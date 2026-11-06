#!/bin/bash
# 不要求 Xcode.app。CLT 提供 swiftc 和 macOS SDK；源码按 Swift 5 编译、最低运行 macOS 12。
set -euo pipefail
cd "$(dirname "$0")"
project_dir="$PWD"
binary_only=false
app_shell=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --binary-only) binary_only=true; shift ;;
        --app-shell)
            [ "$#" -ge 2 ] || { echo "--app-shell 后需要 .app 路径" >&2; exit 2; }
            app_shell="$2"; shift 2 ;;
        -h|--help)
            echo '用法: ./build.sh [--binary-only] [--app-shell /路径/JDGold.app]'
            exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done
[ "$(uname -s)" = Darwin ] || { echo "请在 Mac 的终端执行此脚本。" >&2; exit 1; }
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --find swiftc >/dev/null

# 只有 main.swift 附件，没有图标与 Info.plist，因此默认复用用户已有的应用外壳。
# 保留 Bundle ID：旧 UserDefaults 与钥匙串都依靠这一标识找到原配置。
if ! "$binary_only"; then
    if [ -n "$app_shell" ]; then
        [ -d "$app_shell/Contents" ] || { echo "应用外壳不存在: $app_shell" >&2; exit 1; }
    else
        for candidate in "$project_dir/JDGold.app" /Applications/JDGold.app "$HOME/Applications/JDGold.app"; do
            if [ -d "$candidate/Contents" ]; then app_shell="$candidate"; break; fi
        done
        [ -n "$app_shell" ] || [ -f Info.plist ] || {
            echo '没有找到应用外壳。请执行 ./build.sh --app-shell "/你的路径/JDGold.app"，或仅生成可执行文件：./build.sh --binary-only' >&2
            exit 1
        }
    fi
fi

build_temp="$(mktemp -d "${TMPDIR:-/tmp}/jdgold-build.XXXXXX")"
trap 'rm -rf "$build_temp"' EXIT
find "$project_dir/Sources" -name '*.swift' -type f -print0 > "$build_temp/sources.list"
sources=()
while IFS= read -r -d '' source_file; do sources+=("$source_file"); done < "$build_temp/sources.list"
[ "${#sources[@]}" -gt 0 ] || { echo '未找到 Sources/*.swift' >&2; exit 1; }
products=()
for architecture in arm64 x86_64; do
    echo "编译 ${architecture}（最低 macOS 12）…"
    if xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 -O -sdk "$sdk_path" \
        -target "${architecture}-apple-macosx12.0" -framework Cocoa -framework Security -framework SwiftUI -framework UserNotifications -framework ServiceManagement \
        "${sources[@]}" -o "$build_temp/JDGold-${architecture}" > "$build_temp/${architecture}.log" 2>&1; then
        products+=("$build_temp/JDGold-${architecture}")
    else
        cat "$build_temp/${architecture}.log" >&2
        echo "本机工具链未完成 ${architecture} 编译。" >&2
    fi
done
[ "${#products[@]}" -gt 0 ] || { echo '编译失败，未替换任何应用。' >&2; exit 1; }
if [ "${#products[@]}" -eq 2 ]; then
    xcrun lipo -create "${products[@]}" -output "$build_temp/JDGold"
else
    cp "${products[0]}" "$build_temp/JDGold"
    echo '已回退为单架构产物。'
fi
chmod +x "$build_temp/JDGold"
codesign --force --sign - "$build_temp/JDGold"
echo '运行核心自测（不访问真实行情、推送、偏好或钥匙串）…'
"$build_temp/JDGold" --selftest
cp "$build_temp/JDGold" "$project_dir/JDGold"
if "$binary_only"; then
    echo "完成：$project_dir/JDGold"
    exit 0
fi

new_app="$build_temp/JDGold.app"
if [ -n "$app_shell" ]; then
    ditto "$app_shell" "$new_app"
else
    mkdir -p "$new_app/Contents/MacOS" "$new_app/Contents/Resources"
    cp Info.plist "$new_app/Contents/Info.plist"
    if [ -d Resources ]; then ditto Resources "$new_app/Contents/Resources"; fi
fi
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$new_app/Contents/Info.plist")"
[ "$executable_name" = JDGold ] || { echo '外壳 CFBundleExecutable 必须为 JDGold，已停止替换。' >&2; exit 1; }
# 仅更新新副本的最低系统版本；Bundle ID、图标与原许可证保持原值。
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 12.0' "$new_app/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 12.0' "$new_app/Contents/Info.plist"
mkdir -p "$new_app/Contents/MacOS"
cp "$build_temp/JDGold" "$new_app/Contents/MacOS/JDGold"
# 有原 LICENSE 时逐字复制；没有时不生成冒充原版的许可证。
if [ -f LICENSE ]; then cp LICENSE "$new_app/Contents/Resources/LICENSE"; fi
plutil -lint "$new_app/Contents/Info.plist"
codesign --force --deep --sign - "$new_app"
codesign --verify --deep --strict "$new_app"
if [ -e "$project_dir/JDGold.app" ]; then
    backup_dir="$(mktemp -d "$project_dir/JDGold-previous.XXXXXX")"
    mv "$project_dir/JDGold.app" "$backup_dir/JDGold.app"
    echo "原工程内应用已备份：$backup_dir/JDGold.app"
fi
mv "$new_app" "$project_dir/JDGold.app"
echo "完成：$project_dir/JDGold.app（安装在应用程序中的原版本未修改）"
