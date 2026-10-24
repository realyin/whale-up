#!/bin/bash
# 给桌宠装二次元语音：在 Application Support 里单独建一个 Python 环境装 edge-tts（微软在线语音，免费、不需要 Key）。
# 微软会不定期更换校验方式，语音生成失败时重新运行本脚本升级即可；失败期间 App 会自动改用系统语音。
set -euo pipefail
DIR="$HOME/Library/Application Support/WhaleUp/tts"
python3 -m venv "$DIR"
"$DIR/bin/pip" install -q -U pip edge-tts
"$DIR/bin/edge-tts" --version
echo "已安装到 $DIR"
