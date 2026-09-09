import DesignSystem
import PersistenceKit
import SwiftUI

struct MyPagePresentation {
    let profile: UserProfileDTO?
    let tier: SubscriptionTier

    var displayName: String {
        let value = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "旅行者" : value
    }

    var accountBadgeTitle: String {
        tier.displayName
    }

    var placementSummary: String {
        guard let score = profile?.placementScore else { return "等待校准" }
        return "校准 \(score) / 100"
    }

    var accountBadgeTint: Color {
        return tier == .free ? .secondary : .dsSky
    }
}

struct MyPageEntryRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    init(_ title: String, subtitle: String, icon: String, tint: Color) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(DSSpacing.sm)
        .contentShape(Rectangle())
    }
}
