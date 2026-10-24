#!/bin/bash
# 编译并安装到“应用程序”文件夹，然后启动。首次从这里启动会自动设为开机启动。
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh
pkill -f "WhaleUp.app/Contents/MacOS/WhaleUp" || true
# 改名前的旧版本（专注守护 / FocusGuard.app）：退出并删掉，数据会在新版第一次启动时搬过去
pkill -f "FocusGuard.app/Contents/MacOS/FocusGuard" || true
sleep 1
rm -rf /Applications/FocusGuard.app
rm -rf /Applications/WhaleUp.app
ditto build/WhaleUp.app /Applications/WhaleUp.app
open /Applications/WhaleUp.app
echo "已安装到 /Applications/WhaleUp.app 并启动"
