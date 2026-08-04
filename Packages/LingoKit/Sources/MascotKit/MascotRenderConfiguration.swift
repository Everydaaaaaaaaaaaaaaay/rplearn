import Foundation

/// 渲染器对材质的处理策略。业务层可切换风格，不接触 SceneKit 材质对象。
public enum MascotMaterialStrategy: Equatable, Sendable {
    /// 完整保留模型文件中的材质与光照模型。
    case source
    /// 只显示原始色块，不计算表面光照。
    case flat
    /// 保留体积关系，但将连续明暗压缩为动画式软分级。
    case softToon(MascotToonStyle)
}

/// 三渲二材质参数。所有数值都能按页面或主题覆盖。
public struct MascotToonStyle: Equatable, Sendable {
    public var shadowThreshold: Float
    public var transitionSoftness: Float
    public var shadowBrightness: Float
    public var decorativeMaterialNameTokens: [String]

    public init(
        shadowThreshold: Float = 0.68,
        transitionSoftness: Float = 0.055,
        shadowBrightness: Float = 0.72,
        decorativeMaterialNameTokens: [String] = ["eye", "line", "navy"]
    ) {
        self.shadowThreshold = shadowThreshold
        self.transitionSoftness = transitionSoftness
        self.shadowBrightness = shadowBrightness
        self.decorativeMaterialNameTokens = decorativeMaterialNameTokens
    }

    public static let appDefault = Self()
}

/// 正交镜头构图参数，避免近大远小破坏扁平动画感。
public struct MascotCameraConfiguration: Equatable, Sendable {
    public var framingPadding: Float
    public var verticalOffset: Float
    public var depthMultiplier: Float

    public init(
        framingPadding: Float = 1.12,
        verticalOffset: Float = 0,
        depthMultiplier: Float = 2.4
    ) {
        self.framingPadding = framingPadding
        self.verticalOffset = verticalOffset
        self.depthMultiplier = depthMultiplier
    }
}

/// 舞台光照参数。默认只保留柔和的自阴影，不创建写实地面。
public struct MascotLightingConfiguration: Equatable, Sendable {
    public var ambientIntensity: Float
    public var keyLightIntensity: Float
    public var castsShadows: Bool

    public init(
        ambientIntensity: Float = 360,
        keyLightIntensity: Float = 820,
        castsShadows: Bool = true
    ) {
        self.ambientIntensity = ambientIntensity
        self.keyLightIntensity = keyLightIntensity
        self.castsShadows = castsShadows
    }
}

/// 一个页面所需的完整吉祥物渲染配置。
public struct MascotRenderConfiguration: Equatable, Sendable {
    public var materialStrategy: MascotMaterialStrategy
    public var camera: MascotCameraConfiguration
    public var lighting: MascotLightingConfiguration
    public var preferredFramesPerSecond: Int

    public init(
        materialStrategy: MascotMaterialStrategy = .softToon(.appDefault),
        camera: MascotCameraConfiguration = .init(),
        lighting: MascotLightingConfiguration = .init(),
        preferredFramesPerSecond: Int = 30
    ) {
        self.materialStrategy = materialStrategy
        self.camera = camera
        self.lighting = lighting
        self.preferredFramesPerSecond = preferredFramesPerSecond
    }

    public static let appDefault = Self()
}
