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

    @Test("三位开局角色的稳定头像键都能解析为随包新版头像")
    func starterCharacterPortraitsAreBundled() throws {
        for name in ["avatar_oliver", "avatar_ruby", "avatar_marcus"] {
            #expect(DSAvatarAssets.image(named: name) != nil, "\(name) must resolve locally")
            let actual = try render(imageName: name, pending: false)
            let fallback = try render(imageName: nil, pending: false)
            #expect(actual != fallback, "\(name) must not render the initial-letter fallback")
        }
    }

    @Test("全身源图使用分别校准的头肩裁切，不再共享小头像参数")
    func starterPortraitCropsFillAvatar() {
        let ruby = DSAvatarAssets.presentation(named: "avatar_ruby")
        let marcus = DSAvatarAssets.presentation(named: "avatar_marcus")

        #expect(ruby.alignment == .top)
        #expect(marcus.alignment == .top)
        #expect(ruby.scale >= 1.9)
        #expect(marcus.scale > ruby.scale)
        #expect(ruby.yOffset <= 0)
        #expect(marcus.yOffset <= 0)
    }

    @Test("同一远程头像的并发请求只下载和解码一次")
    func coalescesConcurrentRemoteLoads() async throws {
        let data = try #require(solidImage(.systemPink).pngData())
        let source = AvatarTestDataSource(data: data)
        let cache = AvatarImageCache(dataLoader: { url in
            await source.load(url)
        })
        let url = try #require(URL(string: "https://example.com/avatar.png"))

        let loaded = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await cache.image(for: url) != nil
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let requestCount = await source.requestCount()
        #expect(loaded.allSatisfy { $0 })
        #expect(requestCount == 1)
    }

    @Test("已缓存远程头像在新徽章首帧同步显示")
    func cachedRemoteImageRendersImmediately() throws {
        let url = try #require(URL(string: "https://example.com/cached-avatar.png"))
        AvatarImageCache.shared.insert(solidImage(.systemPink), for: url)
        defer { AvatarImageCache.shared.removeImage(for: url) }

        let actual = try render(imageName: nil, pending: true, remoteURL: url)
        let fallback = try render(imageName: nil, pending: true)
        #expect(actual != fallback)
    }

    private func render(
        imageName: String?,
        pending: Bool,
        remoteURL: URL? = nil
    ) throws -> Data {
        let renderer = ImageRenderer(content:
            AvatarBadge(
                name: "Oliver",
                size: 64,
                imageName: imageName,
                remoteURL: remoteURL,
                usesPendingPlaceholder: pending
            )
                .padding(12)
                .background(.white)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
    }
}

private actor AvatarTestDataSource {
    private let data: Data
    private var requests = 0

    init(data: Data) {
        self.data = data
    }

    func load(_ url: URL) async -> Data? {
        _ = url
        requests += 1
        try? await Task.sleep(for: .milliseconds(40))
        return data
    }

    func requestCount() -> Int {
        requests
    }
}
