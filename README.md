# 专注守护 FocusGuard

一个 Mac 菜单栏小助手。发现你在刷短视频、刷没营养的内容刷太久了，就弹窗劝你去休息；深夜会劝你去睡觉。

## 它怎么判断

每 5 秒看一次前台在用什么：

- **App**：名字里含“抖音、快手、小红书、微博、哔哩哔哩…”的应用
- **浏览器网址**：Safari / Chrome / Edge / Brave / Arc 当前标签页是不是 douyin.com、bilibili.com、youtube.com/shorts 等

连续刷满 **20 分钟**（夜间 23:00–6:00 为 **5 分钟**）就提醒：

- 点“好，关掉它”：只关掉**当前正在看**的那个网页，浏览器和其他标签页都不动（窗口里只剩这一页时变成空白页）；如果是抖音这类 App 就直接退出
- 点“再刷 5 分钟”：5 分钟后还在刷会再提醒，语气会越来越认真

键鼠 5 分钟没动算人不在，不计时；离开这些内容超过 5 分钟，连续时长清零。

## 强制关闭模式

在菜单里勾选“强制关闭模式”后（默认关闭）：

- 在 `forceCloseSites` 里的网站（默认抖音、快手、B 站、TikTok、YouTube Shorts）上**连续**看满 **30 分钟**，当前网页会被**直接关掉**，不再询问
- 关之前 1 分钟，右上角会提示一次
- 关掉后 **15 分钟**内再打开这些网站，会被立刻关掉
- “暂停 1 小时”不会停掉强制关闭，想停只能在菜单里取消勾选

所有判断都在本机完成，不联网、不上传任何数据。

## 编译运行

```bash
./scripts/build_app.sh
open build/FocusGuard.app
```

菜单栏会出现 🌱（正在刷时变成 👀，后面的数字是今天累计分钟数）。

第一次在浏览器里检测时，系统会问“是否允许 FocusGuard 控制 Safari/Chrome”，请点**允许**，否则读不到网址。
构建脚本会优先用本机的 Apple Development 证书签名，这样重新编译后不用再次授权。
想开机自启：把 `FocusGuard.app` 拖进“应用程序”文件夹，再在菜单里勾选“开机自动启动”。

## 修改规则

**最快的方法：** 在浏览器里打开想管的网站，点菜单栏 🌱 →“把 xxx.com 加入…”，再选“没营养网站”或“强制关闭网站”。

**设置页：** 菜单 →“设置…”（⌘,），有四个标签页：

- **网站 / App**：没营养的网站和 App 列表。顶部会显示浏览器当前网页，点“添加这个网站”就能加进去；也可以直接粘贴网址（会自动只保留域名），或手动输入 `youtube.com/shorts` 这样带路径的规则。选中后按删除键或点“删除所选”可以移除
- **强制关闭**：开关、时限、冷却时间，以及强制关闭的网站列表
- **提醒**：白天/夜间提醒时长、夜间时段等

改动立即生效。所有设置保存在 `~/Library/Application Support/FocusGuard/config.json`，也可以直接编辑这个文件。

## 开发

```bash
swift test                                   # 规则与计时逻辑的单元测试
FOCUSGUARD_DEBUG=1 build/FocusGuard.app/Contents/MacOS/FocusGuard   # 在终端打印每次检测结果
FOCUSGUARD_RENDER_NUDGE=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard  # 把弹窗渲染成 PNG
FOCUSGUARD_RENDER_SETTINGS=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard  # 把设置页渲染成 PNG
FOCUSGUARD_CLOSE_JUNK=com.google.Chrome build/FocusGuard.app/Contents/MacOS/FocusGuard  # 关掉当前标签页（若在没营养的网站上）
```

代码结构：`Sources/FocusGuardCore` 是纯逻辑（分类、计时、文案），`Sources/FocusGuard` 是菜单栏 App（系统监测、弹窗）。

## 已知限制

- Firefox 不支持读取网址，只能按 App 判断
- 只看“在哪个网站/App”，不看具体内容。后续可以加 AI 判断内容是否有营养
