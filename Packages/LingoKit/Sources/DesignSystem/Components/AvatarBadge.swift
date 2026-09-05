import SwiftUI
import UIKit

public struct AvatarBadge: View {
    private let name: String
    private let tint: Color?
    private let size: CGFloat
    private let imageName: String?
    private let remoteURL: URL?

    private static let palette: [Color] = [
        .dsSky, .dsCyan, .dsSunset, .dsSuccess, .dsQuiz, .pink,
    ]

    public init(
        name: String,
        tint: Color? = nil,
        size: CGFloat = 46,
        imageName: String? = nil,
        remoteURL: URL? = nil
    ) {
        self.name = name
        self.tint = tint
        self.size = size
        self.imageName = imageName
        self.remoteURL = remoteURL
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
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let remoteURL {
            AsyncImage(url: remoteURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    localAvatarContent
                }
            }
        } else {
            localAvatarContent
        }
    }

    @ViewBuilder
    private var localAvatarContent: some View {
        // Older character cards can reference assets that are not bundled with the app.
        // SwiftUI's named Image renders nothing in that case, so resolve it first.
        if let imageName, !imageName.isEmpty, let image = UIImage(named: imageName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackContent
        }
    }

    private var fallbackContent: some View {
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
