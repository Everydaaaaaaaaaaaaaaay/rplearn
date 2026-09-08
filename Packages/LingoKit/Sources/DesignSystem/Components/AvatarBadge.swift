import SwiftUI
import UIKit

public struct AvatarBadge: View {
    private struct LoadedRemoteImage {
        let url: URL
        let image: UIImage
    }

    private let name: String
    private let tint: Color?
    private let size: CGFloat
    private let remoteURL: URL?
    private let usesPendingPlaceholder: Bool
    private let localImage: UIImage?
    @State private var loadedRemoteImage: LoadedRemoteImage?

    private static let palette: [Color] = [
        .dsSky, .dsCyan, .dsSunset, .dsSuccess, .dsQuiz, .pink,
    ]

    public init(
        name: String,
        tint: Color? = nil,
        size: CGFloat = 46,
        imageName: String? = nil,
        remoteURL: URL? = nil,
        usesPendingPlaceholder: Bool = false
    ) {
        self.name = name
        self.tint = tint
        self.size = size
        self.remoteURL = remoteURL
        self.usesPendingPlaceholder = usesPendingPlaceholder
        self.localImage = DSAvatarAssets.image(named: imageName)
        _loadedRemoteImage = State(
            initialValue: remoteURL.flatMap { url in
                AvatarImageCache.shared.cachedImage(for: url).map {
                    LoadedRemoteImage(url: url, image: $0)
                }
            }
        )
    }

    private var stableTint: Color {
        guard let tint else {
            let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
            return Self.palette[Int(value.magnitude % UInt(Self.palette.count))]
        }
        return tint
    }

    public var body: some View {
        ZStack {
            avatarContent
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: max(1, size / 34))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: stableTint.opacity(0.13), radius: size * 0.12, y: size * 0.045)
        .accessibilityLabel(usesPendingPlaceholder && remoteURL == nil && localImage == nil ? "\(name)，头像待定" : name)
        .task(id: remoteURL) {
            guard let remoteURL else {
                loadedRemoteImage = nil
                return
            }
            if let cached = AvatarImageCache.shared.cachedImage(for: remoteURL) {
                loadedRemoteImage = LoadedRemoteImage(url: remoteURL, image: cached)
                return
            }
            if loadedRemoteImage?.url != remoteURL {
                loadedRemoteImage = nil
            }
            guard let image = await AvatarImageCache.shared.image(for: remoteURL) else { return }
            loadedRemoteImage = LoadedRemoteImage(url: remoteURL, image: image)
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let loadedRemoteImage, loadedRemoteImage.url == remoteURL {
            Image(uiImage: loadedRemoteImage.image)
                .resizable()
                .scaledToFill()
        } else {
            localAvatarContent
        }
    }

    @ViewBuilder
    private var localAvatarContent: some View {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .background(stableTint.opacity(0.15))
        } else {
            fallbackContent
        }
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if usesPendingPlaceholder {
            ZStack {
                Color.dsSky
                Circle()
                    .fill(Color.dsSkyDeep)
                    .frame(width: size * 1.3, height: size * 1.3)
                    .offset(x: size * 0.45, y: size * 0.55)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
        } else {
            initialsContent
        }
    }

    private var initialsContent: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [stableTint.opacity(0.22), stableTint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .black, design: .rounded))
                .foregroundStyle(stableTint)
        }
    }
}
