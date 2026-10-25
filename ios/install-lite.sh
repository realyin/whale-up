#!/bin/bash
# 免费版：编译并装到连着的 iPhone 上。免费开发者账号签的 App 7 天后会过期，过期了再跑一次就行。
# 用法：./install-lite.sh [设备 ID]（不填就用第一台连着的 iPhone）
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '(/connected/ || /available/) && /iPhone/ {print $3; exit}')}"
[ -n "$DEVICE" ] || { echo "没找到连着的 iPhone：用数据线连上，并在手机上打开“开发者模式”"; exit 1; }
xcodegen generate --spec project-lite.yml >/dev/null
xcodebuild -project WhaleUpLite.xcodeproj -scheme WhaleUpLite -destination 'generic/platform=iOS' \
    -derivedDataPath build-lite -allowProvisioningUpdates -quiet build
xcrun devicectl device install app --device "$DEVICE" build-lite/Build/Products/Debug-iphoneos/WhaleUpLite.app >/dev/null
xcrun devicectl device process launch --device "$DEVICE" io.github.realyin.whaleup.lite >/dev/null
echo "已装到 iPhone 并打开。第一次装要在手机“设置 → 通用 → VPN 与设备管理”里信任你的开发者证书。"
