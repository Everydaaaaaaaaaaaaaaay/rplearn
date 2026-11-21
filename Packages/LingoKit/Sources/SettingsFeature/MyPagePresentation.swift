import PersistenceKit

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

}
