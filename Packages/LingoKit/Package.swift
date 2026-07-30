// swift-tools-version: 6.0
import PackageDescription

// LingoKit — 全部 Module target 与依赖图的唯一清单。
// Feature 只按需依赖下层 Module，Feature 之间互不依赖。

func module(_ name: String) -> Target.Dependency {
    .target(name: name)
}

let infraTargets: [Target] = [
    .target(name: "CoreKit"),
    .target(name: "DesignSystem", dependencies: [module("CoreKit")]),
]

let serviceTargets: [Target] = [
    .target(name: "BackendKit", dependencies: [module("CoreKit")]),
    .target(
        name: "BillingKit",
        dependencies: [
            module("BackendKit"),
            module("PersistenceKit"),
        ]
    ),
    .target(name: "LLMKit", dependencies: [module("BackendKit"), module("CoreKit")]),
    .target(name: "SpeechKit", dependencies: [module("CoreKit")]),
    .target(
        name: "MediaKit",
        dependencies: [
            module("BackendKit"),
            module("CoreKit"),
            module("PersistenceKit"),
            module("SpeechKit"),
        ]
    ),
    // DictKit 附带词典卡 UI（DictCardView/浮窗），故依赖 DesignSystem——层级仍严格向下。
    .target(name: "DictKit", dependencies: [module("CoreKit"), module("DesignSystem")]),
    .target(name: "PersistenceKit", dependencies: [module("CoreKit")]),
]

let domainTargets: [Target] = [
    .target(
        name: "DomainKit",
        dependencies: [
            module("CoreKit"),
            module("LLMKit"),
            module("DictKit"),
            module("PersistenceKit"),
        ]
    ),
    .target(name: "StoryEngine"),
    .target(
        name: "SyncKit",
        dependencies: [
            module("BackendKit"),
            module("DomainKit"),
            module("PersistenceKit"),
        ]
    ),
]

func feature(_ name: String, dependencies: [Target.Dependency]) -> Target {
    .target(name: name, dependencies: [module("DesignSystem")] + dependencies)
}

let featureTargets: [Target] = [
    feature("AuthFeature", dependencies: [
        module("BackendKit"),
        module("CoreKit"),
    ]),
    feature("HomeFeature", dependencies: [
        module("CoreKit"),
        module("DomainKit"),
        module("LLMKit"),
        module("PersistenceKit"),
    ]),
    feature("ChatFeature", dependencies: [
        module("CoreKit"),
        module("DomainKit"),
        module("LLMKit"),
        module("PersistenceKit"),
        module("DictKit"),
        module("SpeechKit"),
        module("MediaKit"),
    ]),
    feature("OnboardingFeature", dependencies: [
        module("CoreKit"),
        module("DomainKit"),
        module("StoryEngine"),
        module("PersistenceKit"),
    ]),
    feature("PlacementFeature", dependencies: [
        module("CoreKit"),
        module("DomainKit"),
        module("PersistenceKit"),
        module("SpeechKit"),
    ]),
    feature("StoryFeature", dependencies: [
        module("CoreKit"),
        module("DomainKit"),
        module("StoryEngine"),
        module("PersistenceKit"),
        module("DictKit"),
        module("SpeechKit"),
    ]),
    feature("RosterFeature", dependencies: [
        module("PersistenceKit"),
    ]),
    feature("MapFeature", dependencies: [
        module("DomainKit"),
        module("PersistenceKit"),
    ]),
    feature("FavoritesFeature", dependencies: [
        module("CoreKit"),
        module("PersistenceKit"),
        module("DictKit"),
        module("SpeechKit"),
    ]),
    feature("SettingsFeature", dependencies: [
        module("BackendKit"),
        module("BillingKit"),
        module("CoreKit"),
        module("DomainKit"),
        module("LLMKit"),
        module("PersistenceKit"),
        module("SpeechKit"),
    ]),
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
