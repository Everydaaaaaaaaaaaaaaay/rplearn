import SwiftUI

public struct AvatarBadge: View {
    private let name: String
    private let tint: Color?
    private let size: CGFloat

    private static let palette: [Color] = [
        .dsSky, .dsCyan, .dsSunset, .dsSuccess, .dsQuiz, .pink,
    ]

    public init(name: String, tint: Color? = nil, size: CGFloat = 46) {
        self.name = name
        self.tint = tint
        self.size = size
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
            Circle()
                .fill(
                    LinearGradient(
                        colors: [stableTint.opacity(0.22), stableTint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: max(1, size / 34))
            Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .black, design: .rounded))
                .foregroundStyle(stableTint)
        }
        .frame(width: size, height: size)
        .shadow(color: stableTint.opacity(0.13), radius: size * 0.12, y: size * 0.045)
        .accessibilityLabel(name)
    }
}
