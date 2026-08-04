import MascotKit
import SceneKit
import Testing

@Suite(.serialized)
@MainActor
struct SceneKitMascotLoaderTests {
    @Test("开放 GLB 可组装三动画内容并切换三渲二材质")
    func sceneAndMaterialStrategiesLoad() throws {
        let toon = try SceneKitMascotLoader().load(
            .gugu,
            configuration: .init(materialStrategy: .softToon(.appDefault))
        )
        let flat = try SceneKitMascotLoader().load(
            .gugu,
            configuration: .init(materialStrategy: .flat)
        )

        #expect(toon.geometryNodeCount > 0)
        #expect(toon.geometryNodeCount == flat.geometryNodeCount)
        #expect(toon.availableAnimations == [.idle, .celebrate, .talk])
        #expect(toon.defaultAnimation == .idle)
        #expect(toon.animationCatalog.animations.count == 3)
        #expect(toon.cameraNode.camera?.usesOrthographicProjection == true)
        let bounds = toon.modelRootNode.boundingBox
        let largestVisibleDimension = max(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y
        )
        #expect(
            toon.cameraNode.camera?.orthographicScale ?? .infinity
                < Double(largestVisibleDimension)
        )
        #expect(toon.animationPlayer(for: .idle)?.animation.repeatCount.isInfinite == true)
        #expect(toon.animationPlayer(for: .celebrate)?.animation.repeatCount == 0)
        #expect(toon.animationPlayer(for: .celebrate)?.animation.duration == 3)

        let toonMaterials = materials(in: toon.modelRootNode)
        let flatMaterials = materials(in: flat.modelRootNode)
        #expect(toonMaterials.contains(where: { $0.shaderModifiers?[.fragment] != nil }))
        #expect(toonMaterials.contains(where: { $0.lightingModel == .constant }))
        #expect(flatMaterials.allSatisfy { $0.lightingModel == .constant })
    }

    private func materials(in root: SCNNode) -> [SCNMaterial] {
        var result: [SCNMaterial] = []
        var visited: Set<ObjectIdentifier> = []
        root.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? []
                where visited.insert(ObjectIdentifier(material)).inserted
            {
                result.append(material)
            }
        }
        return result
    }
}
