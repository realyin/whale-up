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

# 本地临时签名，系统权限（自动化）需要一个有效签名的 App
codesign --force --sign - "$APP"
echo "已生成 $APP"
