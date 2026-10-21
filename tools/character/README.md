# 做一个图片角色

桌宠的图片角色 = `~/Library/Application Support/FocusGuard/Mascot/characters/<id>/` 里的若干张透明 PNG + `character.json`。
所有表情帧要**同一个姿势、同一个构图**，否则换表情时人物会跳动。

## 用 Codex 生成表情帧

以原图为参考，每次只改一处（表情或动作），要求纯白背景、去掉文字装饰、尺寸不变。示例提示词见 `prompt-example.txt`：

```bash
codex exec --skip-git-repo-check -s workspace-write -C <素材目录> -i reference.webp < prompt-angry.txt
```

建议生成：`blink`（闭眼，用来眨眼）、`angry`、`watching`、`shy`、`cast`（施法动作），以及小动作 `yawn`、`sleep`、`stretch`、`eat1` / `eat2`（吃饭两帧交替）。

## 打包

`pack_whale.swift` 是鲸鱼娘用的打包脚本：抠白底、擦掉原图上的字、去残渣、把各帧对齐到原图、切出尾巴做摆动部件，并生成 `character.json`。
换别的角色时，按图片修改脚本里的 `textRects`（原图上要擦掉的文字）、`crop`（共用裁剪范围）和 `tailRect`（要单独摆动的部件）。

```bash
swiftc -O pack_whale.swift -o pack && ./pack <素材目录> <输出角色目录>
swift sheet.swift sheet.png a.png b.png ...   # 把几张图拼在一起对比
```

## character.json

| 字段 | 含义 |
|---|---|
| `kind` | `sprite`（图片）或 `live2d` |
| `height` | 显示高度（像素） |
| `images` | 各状态整张图：`idle`、`happy`、`watching`、`angry`、`shy`、`cast`；缺的用头顶符号代替 |
| `blink` | 闭眼帧，平时每 3–6 秒眨一次 |
| `nickname` | 气泡左上角名牌上的名字 |
| `theme` | 气泡配色，键对应 `mascot.css` 里的 CSS 变量：`paper`、`ink`、`accent`、`accent-ink`、`soft`、`soft-ink`、`stitch`、`lace` |
| `actions` | 小动作：`yawn`、`sleep`、`stretch`、`eat`、`swim`、`dance`、`work`、`heart`、`milktea`、`read`，每个是 `{frames, fps, seconds, loop, effect, ownPose}` 或它们的数组（多种姿势，随机挑一种）；多帧按 fps 交替；`ownPose` 为 true 时整张图自带尾巴，不再叠加摆动的尾巴；`effect` 可选 `zzz`/`rice`/`bubbles`/`notes`/`hearts` |
| `parts` | 单独摆动的部件：`image`、`at`（在画布上的左上角）、`pivot`（部件内旋转中心）、`swing`（角度）、`period`（秒） |
| `headAt` / `castFrom` / `castFromCast` | 头顶符号位置、平时 / 施法帧里星星发出的位置（相对角色大小的比例） |
