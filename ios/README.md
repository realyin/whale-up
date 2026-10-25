# 鲸醒 iPhone 版

两个版本，按你的开发者账号选：

| | 免费版（`project-lite.yml`） | 屏幕使用时间版（`project.yml`） |
|---|---|---|
| 账号 | 免费的个人开发者账号就行 | 需要付费的 Apple Developer Program（99 美元/年） |
| 抖音等 App | 快捷指令自动化计时；今天刷够了再打开，跳回鲸醒拦着你 | 系统级限额，用完直接锁上，锁屏页是大肥鱼 |
| 正在刷时到点 | 只能发通知提醒 | 直接锁上 |
| 有没有营养 | Safari 里的视频用 DeepSeek 判断，有营养的不计时 | （还没做） |
| Safari 里刷视频 | Safari 扩展：右下角大肥鱼计时，到点盖上锁屏卡片、停掉视频 | （还没做） |
| 设置和时长 | App 和 Safari 共用一份 | |
| 有效期 | 7 天后要重新装一次 | 一年 |

都需要 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`），先把两个 yml 里的 `DEVELOPMENT_TEAM` 换成你自己的团队 ID。

## 免费版

```bash
./install-lite.sh   # 编译、装到连着的 iPhone 并打开；7 天过期后再跑一次
```

装好后打开鲸醒，点“怎么设置”，照着做两步：

1. **快捷指令自动化**：快捷指令 → 自动化 → ＋ → App → 选抖音等 → “已打开”、“立即运行” → 动作选鲸醒的“开始刷”；再建一个“已关闭”，动作选“刷完了”
2. **Safari 扩展**：设置 → App → Safari 浏览器 → 扩展 → 打开“鲸醒”，网站权限选“允许”；要管哪些网站在鲸醒 App 的“要管的网站”里改；在地址栏点扩展图标能看今天刷了多久、设每天的时长、今天多看或少看

**AI 判断有没有营养**：在鲸醒 App 的“AI 判断有没有营养”里打开、填 DeepSeek 的 API Key（判断标准和 Mac 版同一套）。Safari 里每换一个视频，扩展把标题、作者、简介发给 DeepSeek 判断，同一个视频只问一次；有营养的不计时、头像上显示“✓ 有营养”，没营养的照常计时、到点锁上。抖音等 App 里看不到内容，只能按时长算。

额度用完以后，首页、搜索这类“逛”的页面不锁，只锁没营养的视频页；锁屏卡片上有“回首页找点有营养的”。

调大每天的时长、多看、少看后恢复、从名单删网站，都要照着打一遍随机码（不能复制粘贴）；多看每天最多 2 次。

App 和 Safari 扩展共用同一份设置和今天的总时长（App Group，免费账号也能用）：在哪边改每天的时长、今天多看少看都一样，抖音等 App 和 Safari 里刷的时间加在一起算。

限制：iPhone 不让一个 App 关掉另一个 App，正在刷时到点只能发通知，下次打开才会被拦。

## 屏幕使用时间版

用苹果的 Screen Time API（FamilyControls / DeviceActivity / ManagedSettings）：在 App 里选要管的 App 和网站、设每天的时长，用满就锁上，打开时看到大肥鱼的锁屏页，到第二天凌晨 4 点解锁。

```bash
xcodegen generate
open WhaleUpPhone.xcodeproj   # 在 Xcode 里选你的 iPhone 运行
```

免费账号会报 “Personal development teams … do not support the Family Controls (Development) capability”，这时请用免费版。上架 App Store 还要另外向苹果申请 Family Controls 的分发权限。
