import CoreKit
import SwiftUI
import UIKit

private struct PreparedSceneImage: @unchecked Sendable { let image: UIImage? }

@MainActor
public enum DSSceneImageCache {
    private static let images: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 64 * 1_024 * 1_024
        return value
    }()
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 32 * 1_024 * 1_024
        return value
    }()
    private static var loads: [String: Task<PreparedSceneImage, Never>] = [:]
    private static var thumbnailLoads: [String: Task<PreparedSceneImage, Never>] = [:]

    public static func cachedUIImage(named name: String) -> UIImage? {
        images.object(forKey: name as NSString)
    }

    public static func image(named name: String) -> Image {
        if let value = images.object(forKey: name as NSString) { return Image(uiImage: value) }
        if DownloadableContent.contains("backdrop/" + name),
           let preview = UIImage(named: name + "_preview") { return Image(uiImage: preview) }
        return Image(name)
    }

    public static func loadUIImage(named name: String) async -> UIImage? {
        if let image = cachedUIImage(named: name) { return image }
        if let task = loads[name] { return await task.value.image }
        let task = Task.detached(priority: .userInitiated) {
            if let local = UIImage(named: name) {
                return PreparedSceneImage(image: local.preparingForDisplay() ?? local)
            }
            guard let url = try? await DownloadableContent.file(for: "backdrop/" + name),
                  let image = UIImage(contentsOfFile: url.path) else { return PreparedSceneImage(image: nil) }
            return PreparedSceneImage(image: image.preparingForDisplay() ?? image)
        }
        loads[name] = task
        let decoded = await task.value
        loads[name] = nil
        if let image = decoded.image, let bitmap = image.cgImage {
            images.setObject(image, forKey: name as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        }
        return decoded.image
    }

    public static func cachedThumbnail(named name: String, maxPixelSize: CGFloat = 320) -> UIImage? {
        let key = thumbnailKey(name: name, maxPixelSize: maxPixelSize)
        return thumbnails.object(forKey: key as NSString) ?? images.object(forKey: name as NSString)
    }

    public static func loadThumbnail(named name: String, maxPixelSize: CGFloat = 320) async -> UIImage? {
        let key = thumbnailKey(name: name, maxPixelSize: maxPixelSize)
        if let existing = thumbnails.object(forKey: key as NSString) { return existing }
        let task: Task<PreparedSceneImage, Never>
        if let inflight = thumbnailLoads[key] {
            task = inflight
        } else {
            task = Task.detached(priority: .userInitiated) { decodeThumbnail(named: name, maxPixelSize: maxPixelSize) }
            thumbnailLoads[key] = task
        }
        let value = await task.value
        thumbnailLoads[key] = nil
        if let image = value.image, let bitmap = image.cgImage {
            thumbnails.setObject(image, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        }
        return value.image
    }

    public static func preload(_ names: [String]) async {
        for name in names {
            guard !Task.isCancelled else { return }
            _ = await loadUIImage(named: name)
            await Task.yield()
        }
    }

    public nonisolated static func preloadThumbnails(_ names: [String], maxPixelSize: CGFloat = 320) async {
        let missing = await MainActor.run {
            names.filter { cachedThumbnail(named: $0, maxPixelSize: maxPixelSize) == nil }
        }
        guard !missing.isEmpty else { return }
        for name in missing {
            guard !Task.isCancelled else { return }
            let decoded = decodeThumbnail(named: name, maxPixelSize: maxPixelSize)
            let key = thumbnailKey(name: name, maxPixelSize: maxPixelSize)
            await MainActor.run {
                if let image = decoded.image, let bitmap = image.cgImage,
                   thumbnails.object(forKey: key as NSString) == nil {
                    thumbnails.setObject(image, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
                }
            }
            await Task.yield()
        }
    }

    private nonisolated static func decodeThumbnail(named name: String, maxPixelSize: CGFloat) -> PreparedSceneImage {
        guard let source = UIImage(named: name) ?? UIImage(named: name + "_preview") else {
            return PreparedSceneImage(image: nil)
        }
        let pixelWidth = source.cgImage.map { CGFloat($0.width) } ?? (source.size.width * source.scale)
        let pixelHeight = source.cgImage.map { CGFloat($0.height) } ?? (source.size.height * source.scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return PreparedSceneImage(image: source) }
        let scale = min(1, maxPixelSize / max(pixelWidth, pixelHeight))
        let target = CGSize(
            width: max(1, (pixelWidth * scale).rounded()),
            height: max(1, (pixelHeight * scale).rounded())
        )
        let thumb = source.preparingThumbnail(of: target) ?? source.preparingForDisplay() ?? source
        return PreparedSceneImage(image: thumb)
    }

    private nonisolated static func thumbnailKey(name: String, maxPixelSize: CGFloat) -> String {
        "\(name)@\(Int(maxPixelSize.rounded()))"
    }
}

/// Renders a pre-decoded thumbnail off the main thread so dense multi-photo cards
/// never stall the first frame of a navigation transition.
public struct DSSceneThumbnailImage: View {
    private let name: String
    private let maxPixelSize: CGFloat
    @State private var loaded: UIImage?

    public init(name: String, maxPixelSize: CGFloat = 320) {
        self.name = name
        self.maxPixelSize = maxPixelSize
        _loaded = State(initialValue: DSSceneImageCache.cachedThumbnail(named: name, maxPixelSize: maxPixelSize))
    }

    public var body: some View {
        Group {
            if let image = loaded ?? DSSceneImageCache.cachedThumbnail(named: name, maxPixelSize: maxPixelSize) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.dsTravelNavy.opacity(0.6)
            }
        }
        .task(id: "\(name)@\(Int(maxPixelSize))") {
            if let cached = DSSceneImageCache.cachedThumbnail(named: name, maxPixelSize: maxPixelSize) {
                if loaded !== cached { loaded = cached }
                return
            }
            let decoded = await DSSceneImageCache.loadThumbnail(named: name, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            loaded = decoded
        }
    }
}
