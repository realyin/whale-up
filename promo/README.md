# 「鲸醒」宣传短片

B 站横屏 1920×1080、30fps、约 64 秒的动画短片，用 [Remotion](https://www.remotion.dev/) 写成代码渲染。脚本和分镜见 `script.md`。

```bash
npm install
./scripts/prepare.sh     # 拷贝桌宠角色包、生成她的配音（edge-tts 晓伊）和音效
npm run studio           # 在浏览器里边看边改
npm run render           # 导出 out/promo.mp4
```

- 角色图、配音、音效都在 `public/` 下，不进仓库（角色素材只供个人使用）
- 台词在 `voice-lines.txt`，改了删掉 `public/voice/` 里对应的 mp3 再跑 `prepare.sh`；时间线在 `src/Promo.tsx` 顶上的 `S`
- 背景音乐是 `scripts/bgm.py` 现合成的；想换成自己的，替换 `public/sfx/bgm.mp3` 再导出
