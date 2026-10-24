import Foundation

/// 从旧名字（专注守护 / FocusGuard）升级上来时搬一次家：数据目录、偏好设置挪到新名字下。
/// API Key 在 APIKeyStore 里第一次读取时从旧钥匙串项搬过来。
enum Migration {
    static let oldName = "FocusGuard"
    static let oldBundleID = "com.yinguoliang.focusguard"

    static func run() {
        moveSupportFolder()
        copyDefaults()
    }

    /// ~/Library/Application Support/FocusGuard → WhaleUp。旧路径留一个指向新目录的替身：
    /// Chrome 里“加载已解压”的扩展、语音环境（tts）里写死的路径都还能用
    private static func moveSupportFolder() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent(oldName)
        let new = support.appendingPathComponent("WhaleUp")
        let isLink = (try? fm.destinationOfSymbolicLink(atPath: old.path)) != nil
        guard !isLink, fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            try fm.createSymbolicLink(at: old, withDestinationURL: new)
        } catch {
            NSLog("WhaleUp: 搬数据目录失败 %@", String(describing: error))
        }
    }

    /// 计时状态、桌宠位置、主窗口位置
    private static func copyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFrom\(oldName)"), let old = UserDefaults(suiteName: oldBundleID) else { return }
        let keys = ["tracker": "tracker", "forceCloser": "forceCloser", "mascotHome": "mascotHome",
                    "NSWindow Frame \(oldName)Main": "NSWindow Frame WhaleUpMain"]
        for (from, to) in keys where d.object(forKey: to) == nil {
            if let value = old.object(forKey: from) { d.set(value, forKey: to) }
        }
        d.set(true, forKey: "migratedFrom\(oldName)")
    }
}
