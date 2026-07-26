import SwiftUI

/// 游戏式轻量 HUD 资源槽：首页、地图等场景共享同一视觉与无障碍语义。
public struct DSHUDStat: View {
    private let title: String
    private let value: String
    private let icon: String
    private let tint: Color
    private let usesMonospacedDigits: Bool
    private let foreground: Color
    private let background: Color
    private let accessibilityValue: String

    public init(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        usesMonospacedDigits: Bool = true,
        foreground: Color,
        background: Color,
        accessibilityValue: String? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
        self.usesMonospacedDigits = usesMonospacedDigits
        self.foreground = foreground
        self.background = background
        self.accessibilityValue = accessibilityValue ?? value
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: -1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.58))
                Text(value)
                    .font(
                        .system(
                            .caption,
                            design: usesMonospacedDigits ? .monospaced : .rounded,
                            weight: .heavy
                        )
                    )
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.68), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}
