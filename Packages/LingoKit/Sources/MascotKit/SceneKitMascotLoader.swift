import Foundation
@preconcurrency import GLTFKit2
@preconcurrency import SceneKit
import UIKit

public enum MascotSceneError: LocalizedError, Equatable {
    case missingAnimation(MascotAnimationID)
    case missingDefaultScene
    case emptyGeometry

    public var errorDescription: String? {
        switch self {
        case let .missingAnimation(id):
            "GLB 吉祥物资源缺少动画数据：\(id.rawValue)"
        case .missingDefaultScene:
            "GLB 吉祥物资源没有默认场景"
        case .emptyGeometry:
            "GLB 吉祥物场景不包含可渲染几何体"
        }
    }
}

/// 已加载的 SceneKit 内容。它只管理场景对象，播放策略由更上层状态机决定。
@MainActor
public final class SceneKitMascotContent {
    public let scene: SCNScene
    public let modelRootNode: SCNNode
    public let cameraNode: SCNNode
    public let animationCatalog: MascotAnimationCatalog
    public let defaultAnimation: MascotAnimationID
    public let preferredFramesPerSecond: Int

    private let animationPlayers: [MascotAnimationID: SCNAnimationPlayer]

    init(
        scene: SCNScene,
        modelRootNode: SCNNode,
        cameraNode: SCNNode,
        animationCatalog: MascotAnimationCatalog,
        defaultAnimation: MascotAnimationID,
        preferredFramesPerSecond: Int,
        animationPlayers: [MascotAnimationID: SCNAnimationPlayer]
    ) {
        self.scene = scene
        self.modelRootNode = modelRootNode
        self.cameraNode = cameraNode
        self.animationCatalog = animationCatalog
        self.defaultAnimation = defaultAnimation
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.animationPlayers = animationPlayers
    }

    public var availableAnimations: Set<MascotAnimationID> {
        Set(animationPlayers.keys)
    }

    public var geometryNodeCount: Int {
        var count = 0
        modelRootNode.enumerateChildNodes { node, _ in
            if node.geometry != nil {
                count += 1
            }
        }
        return count
    }

    public func animationPlayer(for id: MascotAnimationID) -> SCNAnimationPlayer? {
        animationPlayers[id]
    }
}

/// 将开放 GLB 资源组装为可播放、可换材质策略的 SceneKit 场景。
@MainActor
public struct SceneKitMascotLoader {
    private struct TemplateKey: Hashable {
        let assetID: MascotAssetID
        let modelURL: URL
    }

    private final class Template {
        let rootNode: SCNNode
        let animations: [MascotAnimationID: SCNAnimation]

        init(rootNode: SCNNode, animations: [MascotAnimationID: SCNAnimation]) {
            self.rootNode = rootNode
            self.animations = animations
        }
    }

    private static var templateCache: [TemplateKey: Template] = [:]

    private let assetProvider: any MascotResourceProviding

    public init(
        assetProvider: any MascotResourceProviding = BundledMascotResourceProvider.packageResources
    ) {
        self.assetProvider = assetProvider
    }

    public func load(
        _ id: MascotAssetID,
        configuration: MascotRenderConfiguration = .appDefault
    ) throws -> SceneKitMascotContent {
        let asset = try assetProvider.loadAsset(id)
        let template = try loadTemplate(asset: asset)
        let scene = SCNScene()
        for child in template.rootNode.childNodes {
            scene.rootNode.addChildNode(child.clone())
        }
        let modelRoot = scene.rootNode
        isolateGeometryAndMaterials(in: modelRoot)

        var geometryCount = 0
        modelRoot.enumerateChildNodes { node, _ in
            if node.geometry != nil {
                geometryCount += 1
            }
        }
        guard geometryCount > 0 else {
            throw MascotSceneError.emptyGeometry
        }
        let players = try makeAnimationPlayers(
            asset: asset,
            animations: template.animations,
            targetRoot: modelRoot
        )
        applyMaterialStrategy(configuration.materialStrategy, to: modelRoot)
        let cameraNode = configureStage(
            scene: scene,
            modelRoot: modelRoot,
            camera: configuration.camera,
            lighting: configuration.lighting
        )

        return SceneKitMascotContent(
            scene: scene,
            modelRootNode: modelRoot,
            cameraNode: cameraNode,
            animationCatalog: asset.catalog,
            defaultAnimation: asset.catalog.defaultAnimation,
            preferredFramesPerSecond: configuration.preferredFramesPerSecond,
            animationPlayers: players
        )
    }

    private func loadTemplate(
        asset: MascotAssetPackage
    ) throws -> Template {
        let key = TemplateKey(
            assetID: asset.id,
            modelURL: asset.modelURL
        )
        if let cached = Self.templateCache[key] {
            return cached
        }

        let gltfAsset = try GLTFAsset(url: asset.modelURL, options: [:])
        let source = GLTFSCNSceneSource(asset: gltfAsset)
        guard let baseScene = source.defaultScene else {
            throw MascotSceneError.missingDefaultScene
        }
        var animations: [MascotAnimationID: SCNAnimation] = [:]
        for id in asset.catalog.animations.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard
                let sourceAnimation = source.animations.first(where: {
                    $0.name == id.rawValue
                }),
                let animation = sourceAnimation.animationPlayer.animation.copy()
                    as? SCNAnimation
            else {
                throw MascotSceneError.missingAnimation(id)
            }

            animations[id] = animation
        }

        // GLB 只解析一次；后续实例克隆场景并建立独立材质域。
        let cleanRoot = SCNNode()
        for child in baseScene.rootNode.childNodes {
            cleanRoot.addChildNode(child.clone())
        }
        cleanRoot.enumerateChildNodes { node, _ in
            node.removeAllAnimations()
        }
        let template = Template(rootNode: cleanRoot, animations: animations)
        Self.templateCache[key] = template
        return template
    }

    private func makeAnimationPlayers(
        asset: MascotAssetPackage,
        animations: [MascotAnimationID: SCNAnimation],
        targetRoot: SCNNode
    ) throws -> [MascotAnimationID: SCNAnimationPlayer] {
        var players: [MascotAnimationID: SCNAnimationPlayer] = [:]
        for (id, templateAnimation) in animations {
            guard
                let animation = templateAnimation.copy() as? SCNAnimation,
                let clip = asset.catalog.animations[id]
            else {
                throw MascotSceneError.missingAnimation(id)
            }
            animation.duration = clip.duration
            animation.repeatCount = clip.repeats ? .infinity : 0
            animation.blendInDuration = clip.crossfadeIn
            animation.blendOutDuration = clip.crossfadeOut
            animation.isAppliedOnCompletion = false
            animation.isRemovedOnCompletion = false
            let player = SCNAnimationPlayer(animation: animation)
            targetRoot.addAnimationPlayer(player, forKey: id.rawValue)
            players[id] = player
        }
        return players
    }

    /// SCNNode.clone 会重绑骨骼，但共享几何与材质；这里为每个实例建立独立材质域。
    private func isolateGeometryAndMaterials(in root: SCNNode) {
        root.enumerateChildNodes { node, _ in
            guard
                let geometry = node.geometry,
                let geometryCopy = geometry.copy() as? SCNGeometry
            else {
                return
            }
            geometryCopy.materials = geometry.materials.map {
                ($0.copy() as? SCNMaterial) ?? $0
            }

            if let skinner = node.skinner {
                let skinnerCopy = SCNSkinner(
                    baseGeometry: geometryCopy,
                    bones: skinner.bones,
                    boneInverseBindTransforms: skinner.boneInverseBindTransforms,
                    boneWeights: skinner.boneWeights,
                    boneIndices: skinner.boneIndices
                )
                skinnerCopy.skeleton = skinner.skeleton
                node.skinner = skinnerCopy
            }
            node.geometry = geometryCopy
        }
    }

    private func applyMaterialStrategy(
        _ strategy: MascotMaterialStrategy,
        to root: SCNNode
    ) {
        guard case .source = strategy else {
            var visited: Set<ObjectIdentifier> = []
            root.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    guard visited.insert(ObjectIdentifier(material)).inserted else {
                        continue
                    }
                    configure(material: material, strategy: strategy)
                }
            }
            return
        }
    }

    private func configure(material: SCNMaterial, strategy: MascotMaterialStrategy) {
        switch strategy {
        case .source:
            return
        case .flat:
            material.lightingModel = .constant
            material.shaderModifiers = nil
            material.specular.contents = UIColor.clear
        case let .softToon(style):
            let lowercasedName = material.name?.lowercased() ?? ""
            let isDecorative = style.decorativeMaterialNameTokens.contains {
                lowercasedName.contains($0.lowercased())
            }
            if isDecorative {
                material.lightingModel = .constant
                material.shaderModifiers = nil
                return
            }

            material.lightingModel = .lambert
            material.isLitPerPixel = true
            material.specular.contents = UIColor.clear
            material.shininess = 0
            material.locksAmbientWithDiffuse = true
            material.shaderModifiers = [.fragment: Self.softToonFragmentShader]
            material.setValue(
                NSNumber(value: style.shadowThreshold),
                forKey: "mascotShadowThreshold"
            )
            material.setValue(
                NSNumber(value: max(style.transitionSoftness, 0.001)),
                forKey: "mascotTransitionSoftness"
            )
            material.setValue(
                NSNumber(value: style.shadowBrightness),
                forKey: "mascotShadowBrightness"
            )
        }
    }

    private func configureStage(
        scene: SCNScene,
        modelRoot: SCNNode,
        camera: MascotCameraConfiguration,
        lighting: MascotLightingConfiguration
    ) -> SCNNode {
        let bounds = modelRoot.boundingBox
        let width = max(bounds.max.x - bounds.min.x, 0.1)
        let height = max(bounds.max.y - bounds.min.y, 0.1)
        let depth = max(bounds.max.z - bounds.min.z, 0.1)
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5 + height * camera.verticalOffset,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        let largestDimension = max(width, max(height, depth))

        let targetNode = SCNNode()
        targetNode.name = "MASCOT_CAMERA_TARGET"
        targetNode.position = center
        scene.rootNode.addChildNode(targetNode)

        let cameraObject = SCNCamera()
        cameraObject.usesOrthographicProjection = true
        cameraObject.orthographicScale = Double(max(width, height) * camera.framingPadding)
        cameraObject.zNear = 0.01
        cameraObject.zFar = Double(largestDimension * 10)
        cameraObject.wantsHDR = false

        let cameraNode = SCNNode()
        cameraNode.name = "MASCOT_CAMERA"
        cameraNode.camera = cameraObject
        cameraNode.position = SCNVector3(
            center.x,
            center.y,
            bounds.max.z + largestDimension * camera.depthMultiplier
        )
        let cameraConstraint = SCNLookAtConstraint(target: targetNode)
        cameraConstraint.isGimbalLockEnabled = true
        cameraNode.constraints = [cameraConstraint]
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = CGFloat(lighting.ambientIntensity)
        ambientLight.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.name = "MASCOT_AMBIENT_LIGHT"
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = CGFloat(lighting.keyLightIntensity)
        keyLight.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        keyLight.castsShadow = lighting.castsShadows
        keyLight.shadowRadius = 6
        keyLight.shadowSampleCount = 8
        keyLight.shadowColor = UIColor.black.withAlphaComponent(0.18)
        let keyNode = SCNNode()
        keyNode.name = "MASCOT_KEY_LIGHT"
        keyNode.light = keyLight
        keyNode.position = SCNVector3(
            center.x - largestDimension,
            center.y + largestDimension,
            bounds.max.z + largestDimension
        )
        let lightConstraint = SCNLookAtConstraint(target: targetNode)
        lightConstraint.isGimbalLockEnabled = true
        keyNode.constraints = [lightConstraint]
        scene.rootNode.addChildNode(keyNode)

        scene.background.contents = UIColor.clear
        return cameraNode
    }

    private static let softToonFragmentShader = """
    #pragma arguments
    float mascotShadowThreshold;
    float mascotTransitionSoftness;
    float mascotShadowBrightness;
    #pragma body
    float baseLuma = max(dot(_surface.diffuse.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.02);
    float litLuma = dot(_output.color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float relativeLight = clamp(litLuma / baseLuma, 0.0, 1.0);
    float lightBand = smoothstep(
        mascotShadowThreshold - mascotTransitionSoftness,
        mascotShadowThreshold + mascotTransitionSoftness,
        relativeLight
    );
    vec3 shadowColor = _surface.diffuse.rgb * mascotShadowBrightness;
    _output.color.rgb = mix(shadowColor, _surface.diffuse.rgb, lightBand);
    """
}
