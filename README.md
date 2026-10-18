# 专注守护 FocusGuard

一个 Mac 菜单栏小助手。发现你在刷短视频、刷没营养的内容刷太久了，就弹窗劝你去休息；深夜会劝你去睡觉。

## 它怎么判断

每 5 秒看一次前台在用什么：

- **App**：名字里含“抖音、快手、小红书、微博、哔哩哔哩…”的应用
- **浏览器网址**：Safari / Chrome / Edge / Brave / Arc 当前标签页是不是 douyin.com、bilibili.com、youtube.com/shorts 等

连续刷满 **20 分钟**（夜间 23:00–6:00 为 **5 分钟**）就提醒。点“再刷 5 分钟”，5 分钟后还在刷会再提醒，语气会越来越认真。
键鼠 5 分钟没动算人不在，不计时；离开这些内容超过 5 分钟，连续时长清零。

所有判断都在本机完成，不联网、不上传任何数据。

## 编译运行

```bash
./scripts/build_app.sh
open build/FocusGuard.app
```

菜单栏会出现 🌱（正在刷时变成 👀，后面的数字是今天累计分钟数）。

第一次在浏览器里检测时，系统会问“是否允许 FocusGuard 控制 Safari/Chrome”，请点**允许**，否则读不到网址。
想开机自启：把 `FocusGuard.app` 拖进“应用程序”文件夹，再在菜单里勾选“开机自动启动”。

## 修改规则

菜单 →“编辑规则…”，会打开 `~/Library/Application Support/FocusGuard/config.json`，保存后自动生效：

| 字段 | 含义 | 默认 |
|---|---|---|
| `daytimeLimitMinutes` / `nightLimitMinutes` | 白天 / 夜间连续多久提醒 | 20 / 5 |
| `nightStartHour` / `nightEndHour` | 夜间时段 | 23 / 6 |
| `snoozeMinutes` | “再刷一会儿”的时长 | 5 |
| `junkApps` | 没营养的 App（名称包含或 Bundle ID） | 抖音、快手… |
| `junkSites` | 没营养的网站，可带路径如 `youtube.com/shorts` | douyin.com… |

## 开发

```bash
swift test                                   # 规则与计时逻辑的单元测试
FOCUSGUARD_DEBUG=1 build/FocusGuard.app/Contents/MacOS/FocusGuard   # 在终端打印每次检测结果
FOCUSGUARD_RENDER_NUDGE=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard  # 把弹窗渲染成 PNG
```

代码结构：`Sources/FocusGuardCore` 是纯逻辑（分类、计时、文案），`Sources/FocusGuard` 是菜单栏 App（系统监测、弹窗）。

## 已知限制

- Firefox 不支持读取网址，只能按 App 判断
- 只看“在哪个网站/App”，不看具体内容。后续可以加 AI 判断内容是否有营养
