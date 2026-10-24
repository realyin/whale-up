import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 被锁住的 App 打开时看到的页面：大肥鱼挥着魔杖
final class ShieldConfig: ShieldConfigurationDataSource {
    private let ink = UIColor(red: 0.12, green: 0.17, blue: 0.37, alpha: 1)
    private let accent = UIColor(red: 0.24, green: 0.44, blue: 0.84, alpha: 1)
    private let paper = UIColor(red: 1, green: 0.99, blue: 0.976, alpha: 1)

    private func make(_ name: String?) -> ShieldConfiguration {
        let s = LimitSettings.load()
        let total = s.dailyMinutes + s.todayExtra
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: paper,
            icon: UIImage(named: "shield-whale"),
            title: .init(text: "今天的 \(total) 分钟用完啦", color: ink),
            subtitle: .init(text: "\(name ?? "这个 App") 已经被大肥鱼施法关上了。\n明天凌晨 \(s.dayStartHour) 点再见～\n真想多看，去鲸醒里自己加时间。", color: ink.withAlphaComponent(0.75)),
            primaryButtonLabel: .init(text: "好吧，去做点别的", color: .white),
            primaryButtonBackgroundColor: accent,
            secondaryButtonLabel: nil)
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(webDomain.domain)
    }
}
