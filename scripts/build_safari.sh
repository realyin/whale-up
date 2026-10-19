#!/bin/bash
# 编译 Safari 扩展（扩展文件直接来自 extension/chrome），装到“应用程序”并运行一次让 Safari 识别
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
xcodebuild -project "extension/safari/FocusGuard Safari/FocusGuard Safari.xcodeproj" -scheme "FocusGuard Safari" \
    -configuration Release -derivedDataPath build/safari-dd \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER="" \
    build | grep -E "error:|BUILD"
rm -rf "/Applications/FocusGuard Safari.app"
ditto "build/safari-dd/Build/Products/Release/FocusGuard Safari.app" "/Applications/FocusGuard Safari.app"
open "/Applications/FocusGuard Safari.app"
echo "已安装。请在 Safari →设置→扩展 里勾选“FocusGuard Safari Extension”，并允许它访问网站"
