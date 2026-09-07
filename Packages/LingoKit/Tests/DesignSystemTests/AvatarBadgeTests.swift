@testable import DesignSystem
import SwiftUI
import Testing
import UIKit

@MainActor
struct AvatarBadgeTests {
    @Test("不存在的本地图片显示与未配置图片相同的备用头像")
    func missingAssetRendersFallback() throws {
        for pending in [false, true] {
            let missing = try render(imageName: "missing-avatar-regression", pending: pending)
            let absent = try render(imageName: nil, pending: pending)
            #expect(missing == absent)
        }
    }

    @Test("Oliver 稳定头像键独立打包，不依赖退役的剧情站姿")
    func oliverUsesBundledStoryPortrait() throws {
        let portrait = try #require(DSAvatarAssets.image(named: "avatar_oliver"))
        #expect(portrait.size.width == portrait.size.height)
        #expect(portrait.size.width >= 256)
        #expect(Bundle.main.url(forResource: "oliver_neutral", withExtension: "png") == nil)
        let actual = try render(imageName: "avatar_oliver", pending: false)
        let fallback = try render(imageName: nil, pending: false)
        #expect(actual != fallback)
    }

    private func render(imageName: String?, pending: Bool) throws -> Data {
        let renderer = ImageRenderer(content:
            AvatarBadge(name: "Oliver", size: 64, imageName: imageName, usesPendingPlaceholder: pending)
                .padding(12)
                .background(.white)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }
}
