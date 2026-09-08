import Foundation
import ImageIO
import UIKit

private final class PreparedAvatarImage: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

/// 所有 `AvatarBadge` 共用的远程头像加载管线。
///
/// 内存缓存让列表中已经显示的头像能被下一级页面同步取得；进行中任务表则保证聊天顶部与
/// 可见消息行只下载、解码同一张远程头像一次。
@MainActor
final class AvatarImageCache {
    typealias DataLoader = @Sendable (URL) async -> Data?

    static let shared = AvatarImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<PreparedAvatarImage?, Never>] = [:]
    private let dataLoader: DataLoader

    init(dataLoader: DataLoader? = nil) {
        images.countLimit = 80
        images.totalCostLimit = 48 * 1_024 * 1_024
        self.dataLoader = dataLoader ?? Self.defaultDataLoader()
    }

    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        let task: Task<PreparedAvatarImage?, Never>
        if let existing = inFlight[url] {
            task = existing
        } else {
            let dataLoader = dataLoader
            task = Task.detached(priority: .userInitiated) {
                guard let data = await dataLoader(url),
                      let image = Self.downsampledImage(from: data)
                else { return nil }
                return PreparedAvatarImage(image: image)
            }
            inFlight[url] = task
        }

        let prepared = await task.value
        inFlight[url] = nil
        guard let prepared else { return nil }
        let pixelCost = prepared.image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(prepared.image, forKey: url as NSURL, cost: pixelCost)
        return prepared.image
    }

    func insert(_ image: UIImage, for url: URL) {
        let pixelCost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: url as NSURL, cost: pixelCost)
    }

    func removeImage(for url: URL) {
        images.removeObject(forKey: url as NSURL)
        inFlight[url]?.cancel()
        inFlight[url] = nil
    }

    private nonisolated static func defaultDataLoader() -> DataLoader {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 24 * 1_024 * 1_024,
            diskCapacity: 128 * 1_024 * 1_024,
            diskPath: "LingoTripAvatarImages"
        )
        let session = URLSession(configuration: configuration)

        return { url in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    return nil
                }
                guard !data.isEmpty, data.count <= 12 * 1_024 * 1_024 else { return nil }
                return data
            } catch {
                return nil
            }
        }
    }

    private nonisolated static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 384,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
