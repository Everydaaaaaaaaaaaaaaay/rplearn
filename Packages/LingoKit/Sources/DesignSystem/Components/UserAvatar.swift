import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

/// A device-local photo belonging to one account. Never shared between account workspaces.
@MainActor @Observable
public final class UserAvatarStore {
    public private(set) var image: UIImage?
    private let fileURL: URL

    public init(accountID: UUID, directory: URL = URL.applicationSupportDirectory) {
        fileURL = directory.appending(path: "LingoTrip/Accounts/\(accountID.uuidString.lowercased())/profile-avatar.jpg")
        if let data = try? Data(contentsOf: fileURL) { image = UIImage(data: data) }
    }

    public func save(photoData: Data) async throws {
        let encoded = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary),
                  let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85)
            else { throw AvatarError.invalidImage }
            return data
        }.value
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: fileURL, options: .atomic)
        image = UIImage(data: encoded)
    }

    private enum AvatarError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "无法读取这张照片，请换一张图片重试。" }
    }
}

public extension EnvironmentValues {
    @Entry var userAvatar: UserAvatarStore? = nil
}

public struct UserAvatar: View {
    @Environment(\.userAvatar) private var store
    private let name: String
    private let size: CGFloat

    public init(name: String = "我", size: CGFloat = 46) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = store?.image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            } else {
                AvatarBadge(name: name, tint: .dsSky, size: size)
            }
        }
        .accessibilityLabel(name)
    }
}
