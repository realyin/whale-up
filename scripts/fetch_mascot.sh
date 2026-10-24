#!/bin/bash
# 可选：下载 Live2D 角色 Mao 用到的第三方文件（不提交进仓库）。默认角色大肥鱼不需要这些。
#   - Live2D Cubism Core（Live2D 专有软件许可）
#   - pixi-live2d-display（MIT）
#   - Live2D 官方示例模型 Mao（Live2D 免费素材许可）
# 这些文件只供本机个人使用；要分发 App 前，请先阅读 Live2D 的许可条款。
# 需要代理时设置 https_proxy 环境变量，curl 会自动使用。
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=mascot/vendor
fetch() { curl -fsSL --retry 3 -o "$1" "$2"; }
mkdir -p "$DEST/lib" "$DEST/Mao"

fetch "$DEST/lib/live2dcubismcore.min.js" https://cubism.live2d.com/sdk-web/cubismcore/live2dcubismcore.min.js
fetch "$DEST/lib/cubism4.min.js" https://cdn.jsdelivr.net/npm/pixi-live2d-display@0.4.0/dist/cubism4.min.js

RAW=https://raw.githubusercontent.com/Live2D/CubismWebSamples/develop/Samples/Resources/Mao
for f in Mao.model3.json Mao.moc3 Mao.physics3.json Mao.pose3.json Mao.cdi3.json Mao.2048/texture_00.png \
         expressions/exp_0{1..8}.exp3.json \
         motions/mtn_0{1..4}.motion3.json motions/sample_01.motion3.json motions/special_0{1..3}.motion3.json; do
    mkdir -p "$DEST/Mao/$(dirname "$f")"
    fetch "$DEST/Mao/$f" "$RAW/$f"
done
echo "已下载到 $DEST（$(du -sh "$DEST" | cut -f1)）"
