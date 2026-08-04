import Foundation
import MascotKit
import Testing

struct MascotResourceProviderTests {
    @Test("内置咕咕资产可加载且动画能力完整")
    func bundledGuguAssetLoads() throws {
        let asset = try BundledMascotResourceProvider.packageResources.loadAsset(.gugu)

        #expect(asset.id == .gugu)
        #expect(asset.modelURL.lastPathComponent == "gugu-v3-animated.glb")
        #expect(FileManager.default.fileExists(atPath: asset.modelURL.path))
        #expect(asset.catalog.defaultAnimation == .idle)
        #expect(asset.catalog.animation(for: .idle) == .idle)
        #expect(asset.catalog.animation(for: .success) == .celebrate)
        #expect(asset.catalog.animation(for: .speaking) == .talk)
        #expect(asset.catalog.animation(for: .answerCorrect) == .celebrate)
        #expect(asset.catalog.clip(.celebrate)?.returnTo == .idle)
        #expect(asset.catalog.clip(.celebrate)?.repeats == false)
    }

    @Test("未知资产返回清晰错误")
    func unsupportedAssetFailsClearly() {
        #expect(throws: MascotResourceError.unsupportedAsset("unknown")) {
            try BundledMascotResourceProvider.packageResources.loadAsset("unknown")
        }
    }
}
