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
                .fill(stableTint.opacity(0.16))
            Circle()
                .stroke(stableTint.opacity(0.28), lineWidth: max(1, size / 32))
            Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(stableTint)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}
