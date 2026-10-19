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

## 统计

菜单里直接显示今天刷没营养内容的总时长，以及最多的 3 个网站或 App。点“查看统计…”会打开统计窗口：

- **最近 7 天**每天刷没营养内容的时长柱状图，点某根柱子可以看那天的明细
- **每天明细**：每个网站 / App 用了多久，可以切换“没营养的 / 全部”。“全部”里也能看到电脑总使用时长
- 网站按域名统计，命中规则的按规则统计（比如 `youtube.com/shorts` 和其他 YouTube 页面分开算）；其他程序按 App 名统计
- 键鼠 5 分钟没动不计时。保留最近 30 天，数据存在 `~/Library/Application Support/FocusGuard/stats.json`，只在本机
- 规则改了，历史数据会按新规则重新归类：比如把知乎加入没营养网站后，以前在知乎上的时间也会算进去

## 内容记录（Chrome 扩展）

装上 Chrome 扩展后，会记下看过的每个视频 / 网页：标题、作者、标签、简介、停留时长、视频看了百分之多少。这是后续用大模型分析“为什么刷、刷了什么”的基础（见 [路线图](docs/roadmap.md)）。

- **记录范围**可在“设置… → 内容记录”里选：只记录没营养网站（默认）/ 记录所有网页 / 不记录
- 只要视频在播放就计时：标签页切到后台、窗口最小化或被挡住也算，单独记为“后台播放”；后台静音播放的不算（通常是没人看的自动预览）。没有视频的网页只在前台且 Chrome 是当前窗口时计时
- 劝导弹窗上可以一键记下“为什么在刷”（累了 / 无聊 / 逃避 / 放松）
- 在统计窗口的“看过的内容”里查看
- 数据存在本机 `~/Library/Application Support/FocusGuard/content.sqlite`，保留 90 天；扩展只把数据发到本机 App（`127.0.0.1:47621`），不上传

**安装扩展（只需一次）：** 菜单 →“设置… → 内容记录”，点“打开扩展文件夹”，然后在 Chrome 的 `chrome://extensions` 打开“开发者模式”，点“加载已解压的扩展程序”，选中 `~/Library/Application Support/FocusGuard/ChromeExtension`。App 更新后，在扩展页点一下刷新按钮。

已实测：B 站视频页（标题、UP 主、标签、时长）。抖音、YouTube 用通用规则提取，需要在登录状态下实际验证。

## AI 判断有没有营养

整个 B 站都在名单里，但 B 站上也有很多学习视频。开启“设置… → AI 判断”后，每条记录下来的内容都会交给大模型判断：

- **有营养**（学习、技术、知识科普等）：不计入没营养时长，不弹窗提醒，不会被强制关闭
- **没营养**（娱乐、搞笑、八卦等）：照常提醒、照常强制关闭；名单外的网站被判没营养也会提醒（需要“记录所有网页”）
- 还没判断出来时（新视频的前十几秒），按网站规则处理
- “你的标准”可以用自己的话写什么算有营养，会原样写进提示词
- 服务商可选 Anthropic（默认用 `claude-haiku-5-5` 判断）、DeepSeek（默认 `deepseek-flash`）、任意 OpenAI 兼容接口、本机 Ollama（内容不出电脑）
- API Key 存在系统钥匙串里；每条内容只发送网站名、标题、作者、标签、简介和视频时长，不发完整网址和观看时间；同一条内容只判断一次
- 判断结果显示在统计窗口的“看过的内容”里；菜单和时长统计里，名单内被判有营养的时长单独记为“xx · 有营养”

前提：需要开启内容记录并安装 Chrome 扩展。

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
FOCUSGUARD_RENDER_STATS=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard     # 用示例数据把统计页渲染成 PNG
FOCUSGUARD_CLOSE_JUNK=com.google.Chrome build/FocusGuard.app/Contents/MacOS/FocusGuard  # 关掉当前标签页（若在没营养的网站上）
```

代码结构：`Sources/FocusGuardCore` 是纯逻辑（分类、计时、文案），`Sources/FocusGuard` 是菜单栏 App（系统监测、弹窗）。

## 已知限制

- Firefox 不支持读取网址，只能按 App 判断
- 只看“在哪个网站/App”，不看具体内容。后续可以加 AI 判断内容是否有营养
