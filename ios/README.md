# 鲸醒 iPhone 版

两个版本，按你的开发者账号选：

| | 免费版（`project-lite.yml`） | 屏幕使用时间版（`project.yml`） |
|---|---|---|
| 账号 | 免费的个人开发者账号就行 | 需要付费的 Apple Developer Program（99 美元/年） |
| 抖音等 App | 快捷指令自动化计时；今天刷够了再打开，跳回鲸醒拦着你 | 系统级限额，用完直接锁上，锁屏页是大肥鱼 |
| 正在刷时到点 | 只能发通知提醒 | 直接锁上 |
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
2. **Safari 扩展**：设置 → App → Safari 浏览器 → 扩展 → 打开“鲸醒”，网站权限选“允许”；在地址栏点扩展图标设每天的时长、今天多看或少看

App 和 Safari 扩展共用同一份设置和今天的总时长（App Group，免费账号也能用）：在哪边改每天的时长、今天多看少看都一样，抖音等 App 和 Safari 里刷的时间加在一起算。

限制：iPhone 不让一个 App 关掉另一个 App，正在刷时到点只能发通知，下次打开才会被拦。

## 屏幕使用时间版

用苹果的 Screen Time API（FamilyControls / DeviceActivity / ManagedSettings）：在 App 里选要管的 App 和网站、设每天的时长，用满就锁上，打开时看到大肥鱼的锁屏页，到第二天凌晨 4 点解锁。

```bash
xcodegen generate
open WhaleUpPhone.xcodeproj   # 在 Xcode 里选你的 iPhone 运行
```

免费账号会报 “Personal development teams … do not support the Family Controls (Development) capability”，这时请用免费版。上架 App Store 还要另外向苹果申请 Family Controls 的分发权限。
