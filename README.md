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
./scripts/install.sh        # 编译、装到“应用程序”并启动；首次安装自动设为开机启动
./scripts/build_safari.sh   # 可选：编译并安装 Safari 扩展
```

菜单栏会出现 🌱（正在刷时变成 👀，后面的数字是今天累计分钟数）。

第一次在浏览器里检测时，系统会问“是否允许 FocusGuard 控制 Safari/Chrome”，请点**允许**，否则读不到网址。
构建脚本会优先用本机的 Apple Development 证书签名，这样重新编译后不用再次授权。开机启动可以在菜单里随时关掉。

## 统计

菜单里直接显示今天刷没营养内容的总时长，以及最多的 3 个网站或 App。点“查看统计…”会打开统计窗口：

- **最近 7 天**每天刷没营养内容的时长柱状图，点某根柱子可以看那天的明细
- **每天明细**：每个网站 / App 用了多久，可以切换“没营养的 / 全部”。“全部”里也能看到电脑总使用时长
- 网站按域名统计，命中规则的按规则统计（比如 `youtube.com/shorts` 和其他 YouTube 页面分开算）；其他程序按 App 名统计
- 键鼠 5 分钟没动不计时。保留最近 30 天，数据存在 `~/Library/Application Support/FocusGuard/stats.json`，只在本机
- 规则改了，历史数据会按新规则重新归类：比如把知乎加入没营养网站后，以前在知乎上的时间也会算进去

## 内容记录（Chrome / Safari 扩展）

装上 Chrome 扩展后，会记下看过的每个视频 / 网页：标题、作者、标签、简介、停留时长、视频看了百分之多少。这是后续用大模型分析“为什么刷、刷了什么”的基础（见 [路线图](docs/roadmap.md)）。

- **记录范围**可在“设置… → 内容记录”里选：只记录没营养网站（默认）/ 记录所有网页 / 不记录
- 只要视频在播放就计时：标签页切到后台、窗口最小化或被挡住也算，单独记为“后台播放”；后台静音播放的不算（通常是没人看的自动预览）。没有视频的网页只在前台且 Chrome 是当前窗口时计时
- 劝导弹窗上可以一键记下“为什么在刷”（累了 / 无聊 / 逃避 / 放松）
- 在统计窗口的“看过的内容”里查看
- 数据存在本机 `~/Library/Application Support/FocusGuard/content.sqlite`，保留 90 天；扩展只把数据发到本机 App（`127.0.0.1:47621`），不上传

**安装扩展（只需一次）：** 菜单 →“设置… → 内容记录”，点“打开扩展文件夹”，然后在 Chrome 的 `chrome://extensions` 打开“开发者模式”，点“加载已解压的扩展程序”，选中 `~/Library/Application Support/FocusGuard/ChromeExtension`。App 更新后，在扩展页点一下刷新按钮。

**Safari：** 运行 `./scripts/build_safari.sh`，然后在 Safari →设置→扩展 里勾选“FocusGuard Safari Extension”并允许访问网站。

已实测：B 站、YouTube、抖音（标题、作者、标签、时长，抖音信息流里每个视频单独一条）。

## AI 判断有没有营养

整个 B 站都在名单里，但 B 站上也有很多学习视频。开启“设置… → AI 判断”后，每条记录下来的内容都会交给大模型判断：

- **有营养**（学习、技术、知识科普等）：不计入没营养时长，不弹窗提醒，不会被强制关闭
- **没营养**（娱乐、搞笑、八卦等）：照常提醒、照常强制关闭；名单外的网站被判没营养也会提醒（需要“记录所有网页”）
- 还没判断出来时（新视频的前十几秒），按网站规则处理
- “你的标准”可以用自己的话写什么算有营养，会原样写进提示词
- 服务商可选 Anthropic（默认用 `claude-haiku-5-5` 判断）、DeepSeek（默认 `deepseek-flash`）、任意 OpenAI 兼容接口、本机 Ollama（内容不出电脑）
- API Key 存在系统钥匙串里；每条内容只发送网站名、标题、作者、标签、简介和视频时长，不发完整网址和观看时间；同一条内容只判断一次
- 判断结果显示在统计窗口的“看过的内容”里；菜单和时长统计里，名单内被判有营养的时长单独记为“xx · 有营养”

前提：需要开启内容记录并安装浏览器扩展。

## 每日小结与每周复盘

开启 AI 判断后，用“写报告用的模型”：

- **每日小结**：每天到点（默认 22:00）自动写当天的：今天概况、往脑子里装了什么、什么时候最容易刷、明天试试；漏写的前一天会补上
- **每周复盘**：每周一自动写上一周的：模式、背后的原因、需要加强什么、有营养的替代、下周的一个承诺
- 在统计窗口的“每日小结”页查看，也可以随时手动写 / 重写
- 同时写进 Obsidian：自动找到当前的库，存到 `专注守护/每日小结/`、`专注守护/每周复盘/`；可在“AI 判断”设置里改文件夹或关闭

## 劝导怎么越来越管用

- **AI 写劝导**：弹窗文案由大模型结合你刚才看的具体内容、时间、你说过的原因来写；4 秒拿不到就用固定文案
- **记住效果**：每次劝导你是“关掉它”还是“再刷”都会记下；下次写劝导时告诉大模型哪种说法对你有效
- **逐级加强**：第二次提醒起“再刷”要等 10 秒；第三次起或额度用完后还要写一句理由（理由也会进入小结和复盘）
- **打开前先停一下**（可选）：从正常内容切到没营养的内容时，先深呼吸几秒再决定
- **每日额度**：一天最多刷多少分钟，用完再刷 1 分钟就提醒，也可以设为用完直接关网页
- **工作时段**：可选星期和时间，期间连续刷几分钟就提醒

## 修改规则

**最快的方法：** 在浏览器里打开想管的网站，点菜单栏 🌱 →“把 xxx.com 加入…”，再选“没营养网站”或“强制关闭网站”。

**设置页：** 菜单 →“设置…”（⌘,）：

- **网站 / App**：没营养的网站和 App 列表。顶部会显示浏览器当前网页，点“添加这个网站”就能加进去；也可以直接粘贴网址（会自动只保留域名），或手动输入 `youtube.com/shorts` 这样带路径的规则。选中后按删除键或点“删除所选”可以移除
- **强制关闭**：开关、时限、冷却时间，以及强制关闭的网站列表
- **提醒**：白天/夜间提醒时长、夜间时段、每日额度、工作时段、逐级加强
- **内容记录**：记录范围、扩展安装
- **AI 判断**：开关、你的标准、服务商与模型、API Key、AI 劝导、小结时间、Obsidian

改动立即生效。所有设置保存在 `~/Library/Application Support/FocusGuard/config.json`，也可以直接编辑这个文件。

## 开发

```bash
swift test                                   # 规则与计时逻辑的单元测试
FOCUSGUARD_DEBUG=1 build/FocusGuard.app/Contents/MacOS/FocusGuard   # 在终端打印每次检测结果
FOCUSGUARD_RENDER_NUDGE=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard  # 把弹窗渲染成 PNG
FOCUSGUARD_RENDER_SETTINGS=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard  # 把设置页渲染成 PNG
FOCUSGUARD_RENDER_STATS=/tmp build/FocusGuard.app/Contents/MacOS/FocusGuard     # 用示例数据把统计页渲染成 PNG
FOCUSGUARD_CLOSE_JUNK=com.google.Chrome build/FocusGuard.app/Contents/MacOS/FocusGuard  # 关掉当前标签页（若在没营养的网站上）
FOCUSGUARD_TEST_LABEL=1 build/FocusGuard.app/Contents/MacOS/FocusGuard    # 用当前配置判断两条示例（会调用大模型）
FOCUSGUARD_TEST_NUDGE=1 build/FocusGuard.app/Contents/MacOS/FocusGuard    # 按最近记录写一条劝导（会调用大模型）
FOCUSGUARD_WRITE_DIGEST=1 build/FocusGuard.app/Contents/MacOS/FocusGuard  # 立刻写今天的小结（会调用大模型）
FOCUSGUARD_WRITE_WEEKLY=1 build/FocusGuard.app/Contents/MacOS/FocusGuard  # 立刻写本周复盘（会调用大模型并写入 Obsidian）
```

代码结构：`Sources/FocusGuardCore` 是纯逻辑（分类、计时、文案），`Sources/FocusGuard` 是菜单栏 App（系统监测、弹窗）。

## 已知限制

- Firefox 不支持读取网址，只能按 App 判断
- AI 判断、小结只覆盖装了扩展的浏览器；抖音等桌面 App 只按名字判断
- 手机还没有，见 [路线图](docs/roadmap.md)
