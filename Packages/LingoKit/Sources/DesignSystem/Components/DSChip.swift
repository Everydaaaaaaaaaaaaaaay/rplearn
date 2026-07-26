import SwiftUI

public struct DSChip: View {
    private let title: String
    private let tint: Color
    private let prominent: Bool

    public init(_ title: String, tint: Color = .dsSky, prominent: Bool = false) {
        self.title = title
        self.tint = tint
        self.prominent = prominent
    }

    public var body: some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(prominent ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(prominent ? tint : tint.opacity(0.09), in: Capsule())
            .overlay {
                if !prominent {
                    Capsule()
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                }
            }
    }
}
