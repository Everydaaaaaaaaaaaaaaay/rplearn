// swift-tools-version: 6.0
import PackageDescription

// LingoKit — 全部模块 target 与依赖图的唯一清单。
// 依赖方向严格向下：Feature → Domain → Service → Infra，Feature 之间互不依赖。

let infraTargets: [Target] = [
    .target(name: "CoreKit"),
    .target(name: "DesignSystem", dependencies: ["CoreKit"]),
]

let serviceTargets: [Target] = [
    .target(name: "LLMKit", dependencies: ["CoreKit"]),
    .target(name: "SpeechKit", dependencies: ["CoreKit"]),
    // DictKit 附带词典卡 UI（DictCardView/浮窗），故依赖 DesignSystem——层级仍严格向下。
    .target(name: "DictKit", dependencies: ["CoreKit", "DesignSystem"]),
    .target(name: "PersistenceKit", dependencies: ["CoreKit"]),
]

let domainTargets: [Target] = [
    .target(name: "DomainKit", dependencies: ["CoreKit", "LLMKit", "SpeechKit", "DictKit", "PersistenceKit"]),
    .target(name: "StoryEngine", dependencies: ["CoreKit"]),
]

func feature(_ name: String, extraDependencies: [Target.Dependency] = []) -> Target {
    .target(name: name, dependencies: ["DomainKit", "DesignSystem"] + extraDependencies)
}

let featureTargets: [Target] = [
    feature("HomeFeature"),
    feature("ChatFeature", extraDependencies: ["LLMKit", "PersistenceKit", "DictKit", "SpeechKit"]),
    feature("OnboardingFeature", extraDependencies: ["StoryEngine"]),
    feature("StoryFeature", extraDependencies: ["StoryEngine"]),
    feature("RosterFeature"),
    feature("MapFeature"),
    feature("FavoritesFeature", extraDependencies: ["PersistenceKit", "DictKit", "SpeechKit"]),
    feature("SettingsFeature", extraDependencies: ["LLMKit"]),
]

// 测试不在此声明：全部测试由 xcodeproj 的 LingoTripTests bundle（App 托管）编译运行，
// 源码位于本 package 的 Tests/ 目录下按被测模块分子目录（见 project.yml）。
// 原因：钥匙串/SwiftData 等测试需要宿主 App 环境，无宿主的 SwiftPM 测试 runner 会报 -34018。

let allTargets = infraTargets + serviceTargets + domainTargets + featureTargets

let package = Package(
    name: "LingoKit",
    platforms: [.iOS(.v18)],
    products: allTargets.map { .library(name: $0.name, targets: [$0.name]) },
    targets: allTargets
)
