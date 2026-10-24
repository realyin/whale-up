#!/bin/bash
# 准备短片素材：拷贝桌宠角色包、生成她的台词配音（edge-tts 晓伊，和桌宠同一个声音）
# 用法：./scripts/prepare.sh [背景图目录]
set -e
cd "$(dirname "$0")/.."
SUPPORT="$HOME/Library/Application Support/FocusGuard"
mkdir -p public/whale public/voice public/bg public/sfx
cp -R "$SUPPORT/Mascot/characters/whale/." public/whale/
[ -n "$1" ] && cp "$1"/bg-*.png public/bg/

TTS="$SUPPORT/tts/bin/edge-tts"
[ -x "$TTS" ] || { echo "先运行 ../scripts/setup_voice.sh 装好 edge-tts"; exit 1; }
# id|台词
while IFS='|' read -r id line; do
  [ -z "$id" ] && continue
  [ -f "public/voice/$id.mp3" ] && continue
  "$TTS" --voice zh-CN-XiaoyiNeural --pitch=+14Hz --rate=+6% --text "$line" --write-media "public/voice/$id.mp3"
  echo "已生成 $id"
done < voice-lines.txt

# 音效：用 ffmpeg 现合成，不依赖素材网站
[ -f public/sfx/pop.mp3 ] || ffmpeg -y -loglevel error -f lavfi -i "aevalsrc='0.6*sin(2*PI*(500+2400*t)*t)*exp(-22*t)':s=44100:d=0.2" public/sfx/pop.mp3
[ -f public/sfx/sparkle.mp3 ] || ffmpeg -y -loglevel error -f lavfi -i "aevalsrc='0.25*sin(2*PI*2093*t)*exp(-7*t)+0.22*sin(2*PI*2637*t)*exp(-7*(t-0.09))*gte(t,0.09)+0.2*sin(2*PI*3136*t)*exp(-7*(t-0.18))*gte(t,0.18)+0.18*sin(2*PI*4186*t)*exp(-7*(t-0.27))*gte(t,0.27)':s=44100:d=0.9" public/sfx/sparkle.mp3
[ -f public/sfx/boom.mp3 ] || ffmpeg -y -loglevel error -f lavfi -i "aevalsrc='0.9*sin(2*PI*(90-40*t)*t)*exp(-5*t)+0.5*(random(0)*2-1)*exp(-9*t)':s=44100:d=0.7" -af "lowpass=f=900" public/sfx/boom.mp3
echo "素材准备好了"
