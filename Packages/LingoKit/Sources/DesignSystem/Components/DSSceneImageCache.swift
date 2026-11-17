import SwiftUI
import UIKit

private struct PreparedSceneImage: @unchecked Sendable { let image: UIImage? }

@MainActor
public enum DSSceneImageCache {
    private static let images: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 48 * 1_024 * 1_024
        return value
    }()
    private static var loads: [String: Task<PreparedSceneImage, Never>] = [:]

    public static func image(named name: String) -> Image {
        if let value = images.object(forKey: name as NSString) { return Image(uiImage: value) }
        return Image(name)
    }

    public static func preload(_ names: [String]) async {
        for name in names {
            guard !Task.isCancelled else { return }
            if images.object(forKey: name as NSString) != nil { continue }
            let task: Task<PreparedSceneImage, Never>
            if let existing = loads[name] { task = existing }
            else {
                task = Task.detached(priority: .utility) {
                    PreparedSceneImage(image: UIImage(named: name)?.preparingForDisplay())
                }
                loads[name] = task
            }
            let value = await task.value
            loads[name] = nil
            if let image = value.image, let bitmap = image.cgImage {
                images.setObject(image, forKey: name as NSString, cost: bitmap.bytesPerRow * bitmap.height)
            }
        }
    }
}
