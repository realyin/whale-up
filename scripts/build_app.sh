#!/bin/bash
# 编译并打包成 build/FocusGuard.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FocusGuard"

APP=build/FocusGuard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FocusGuard"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FocusGuard</string>
    <key>CFBundleDisplayName</key><string>专注守护</string>
    <key>CFBundleIdentifier</key><string>com.yinguoliang.focusguard</string>
    <key>CFBundleExecutable</key><string>FocusGuard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>专注守护需要读取浏览器当前标签页的网址，用来判断你是不是在刷短视频。网址只在本机判断，不会上传。</string>
</dict>
</plist>
PLIST

# 签名。优先用本机的 Apple Development 证书：签名身份固定，重新编译后不用再次授权“控制浏览器”。
# 没有证书时退回临时签名（每次编译后系统会重新询问授权）。
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "签名：${IDENTITY:-临时签名}"
echo "已生成 $APP"
