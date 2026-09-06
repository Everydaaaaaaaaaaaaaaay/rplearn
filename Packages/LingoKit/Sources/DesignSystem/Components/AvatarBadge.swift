import SwiftUI

public struct AvatarBadge: View {
    private let name: String
    private let tint: Color?
    private let size: CGFloat
    private let imageName: String?
    private let remoteURL: URL?
    private let usesPendingPlaceholder: Bool

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
        self.imageName = imageName
        self.remoteURL = remoteURL
        self.usesPendingPlaceholder = usesPendingPlaceholder
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
        .accessibilityLabel(usesPendingPlaceholder && remoteURL == nil && imageName == nil ? "\(name)，头像待定" : name)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let remoteURL {
            AsyncImage(url: remoteURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackContent
                }
            }
        } else if let imageName, !imageName.isEmpty {
            Image(imageName)
                .resizable()
                .scaledToFill()
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
