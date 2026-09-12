import DesignSystem
import PersistenceKit
import SwiftUI

/// The same starter card is used for selection and the compact welcome illustration.
struct StarterPortraitCard: View {
    let card: CharacterCard
    let city: String
    let flag: String
    var compact = false
    var body: some View {
        let palette = DSScenePalette.city(card.regionID)
        VStack(spacing: compact ? 8 : DSSpacing.md) {
            HStack {
                Text(card.name.split(separator: " ").first.map(String.init) ?? card.name)
                    .font(.system(size: compact ? 24 : 34, weight: .black, design: .rounded))
                Spacer()
                Text(flag)
                    .font(.system(size: 32))
                    .padding(7)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                    .rotationEffect(.degrees(3))
            }

            AvatarBadge(
                name: card.name,
                tint: .white,
                size: compact ? 64 : 112,
                imageName: card.avatarAssetName,
                remoteURL: card.avatarRemoteURL.flatMap(URL.init(string:))
            )
                .accessibilityIdentifier("onboarding.character.avatar.\(card.regionID)")
                .background(.white.opacity(0.16), in: Circle())

            VStack(spacing: 4) {
                Text("\(card.age) 岁 · \(city) · \(compact ? card.occupation.components(separatedBy: "，").first ?? card.occupation : card.occupation)")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(compact ? card.personality.components(separatedBy: "；").first ?? card.personality : card.personality)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : 3)
                    .opacity(0.88)
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(card.localizedHobbies.prefix(compact ? 2 : 3), id: \.self) { hobby in
                    DSChip(hobby, tint: .white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(compact ? 14 : DSSpacing.lg)
        .frame(maxHeight: 520)
        .background(
            LinearGradient(
                colors: [palette.skyTop, palette.accent, palette.silhouetteNear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 7)
        }
        .shadow(color: palette.silhouetteNear.opacity(0.35), radius: 18, y: 12)
    }
}
