// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v13)],
    targets: [
        // 纯逻辑：规则、分类、计时与提醒决策（可单元测试）
        .target(name: "FocusGuardCore"),
        // 菜单栏应用：系统监测 + 界面
        .executableTarget(name: "FocusGuard", dependencies: ["FocusGuardCore"]),
        .testTarget(name: "FocusGuardCoreTests", dependencies: ["FocusGuardCore"]),
    ]
)
