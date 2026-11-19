import DesignSystem
import SwiftUI
import UIKit

struct ChatTimelineEvent: View {
    enum Kind: Equatable {
        case memory, affinity, mood, appointment

        var icon: String {
            switch self {
            case .memory: "bookmark.fill"
            case .affinity: "heart.fill"
            case .mood: "cloud.fill"
            case .appointment: "calendar.badge.checkmark"
            }
        }

        var tint: Color {
            switch self {
            case .memory:
                Color(light: UIColor(red: 0.39, green: 0.28, blue: 0.59, alpha: 1),
                      dark: UIColor(red: 0.79, green: 0.70, blue: 0.97, alpha: 1))
            case .affinity:
                Color(light: UIColor(red: 0.61, green: 0.24, blue: 0.36, alpha: 1),
                      dark: UIColor(red: 0.99, green: 0.65, blue: 0.76, alpha: 1))
            case .mood:
                Color(light: UIColor(red: 0.29, green: 0.40, blue: 0.56, alpha: 1),
                      dark: UIColor(red: 0.67, green: 0.79, blue: 0.95, alpha: 1))
            case .appointment:
                Color(light: UIColor(red: 0.16, green: 0.43, blue: 0.34, alpha: 1),
                      dark: UIColor(red: 0.59, green: 0.87, blue: 0.74, alpha: 1))
            }
        }
    }

    let kind: Kind
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(kind.tint)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(kind.tint.opacity(kind == .appointment ? 0.13 : 0.095), in: Capsule())
        .overlay { Capsule().strokeBorder(kind.tint.opacity(0.15), lineWidth: 1) }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
