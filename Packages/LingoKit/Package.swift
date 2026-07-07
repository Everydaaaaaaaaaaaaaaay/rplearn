// swift-tools-version: 6.0
import PackageDescription

// LingoKit — 全部模块 target 与依赖图的唯一清单。
// 依赖方向严格向下：Feature → Domain → Service → Infra，Feature 之间互不依赖。

let infraTargets: [Target] = [
    .target(name: "CoreKit"),
    .target(name: "DesignSystem"),
]

let serviceTargets: [Target] = [
    .target(name: "LLMKit", dependencies: ["CoreKit"]),
    .target(name: "SpeechKit", dependencies: ["CoreKit"]),
    .target(name: "DictKit", dependencies: ["CoreKit"]),
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
    feature("ChatFeature"),
    feature("OnboardingFeature", extraDependencies: ["StoryEngine"]),
    feature("StoryFeature", extraDependencies: ["StoryEngine"]),
    feature("RosterFeature"),
    feature("MapFeature"),
    feature("FavoritesFeature"),
    feature("SettingsFeature"),
]

let allTargets = infraTargets + serviceTargets + domainTargets + featureTargets

let package = Package(
    name: "LingoKit",
    platforms: [.iOS(.v18)],
    products: allTargets.map { .library(name: $0.name, targets: [$0.name]) },
    targets: allTargets
)
