#!/bin/bash
# 编译并安装到“应用程序”文件夹，然后启动。首次从这里启动会自动设为开机启动。
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh
pkill -f "FocusGuard.app/Contents/MacOS/FocusGuard" || true
sleep 1
rm -rf /Applications/FocusGuard.app
ditto build/FocusGuard.app /Applications/FocusGuard.app
open /Applications/FocusGuard.app
echo "已安装到 /Applications/FocusGuard.app 并启动"
