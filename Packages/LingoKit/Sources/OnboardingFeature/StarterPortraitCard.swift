import DesignSystem
import PersistenceKit
import SwiftUI

/// The same starter card is used for selection and the compact welcome illustration.
/// 蓬蓬厚卡片：上半是旅伴所在城市的卡通街景，头像压在街景下沿，下半是名字、简介与爱好标签。
struct StarterPortraitCard: View {
    let card: CharacterCard
    let city: String
    let flag: String
    var compact = false

    var body: some View {
        let candy = PuffCandy.stable(for: card.name)
        let avatarSize: CGFloat = compact ? 64 : 104
        VStack(spacing: 0) {
            PuffCityScene(regionID: card.regionID, viewport: .west)
                .frame(height: compact ? 92 : 150)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Text(flag)
                        .font(.system(size: compact ? 22 : 28))
                        .padding(6)
                        .background(Puff.Palette.card, in: RoundedRectangle(cornerRadius: Puff.Radius.small, style: .continuous))
                        .rotationEffect(.degrees(3))
                        .padding(10)
                        .accessibilityHidden(true)
                }
                .padding([.horizontal, .top], 6)

            VStack(spacing: compact ? 8 : Puff.Space.s) {
                PuffAvatar(name: card.name, size: avatarSize,
                           imageName: card.avatarAssetName,
                           remoteURL: card.avatarRemoteURL.flatMap(URL.init(string:)),
                           candy: candy)
                    .padding(5)
                    .background(Puff.Palette.card, in: Circle())
                    .padding(.top, -avatarSize / 2)
                    .accessibilityIdentifier("onboarding.character.avatar.\(card.regionID)")

                Text(card.name.split(separator: " ").first.map(String.init) ?? card.name)
                    .font(.puff(compact ? .title3 : .title, Puff.Weight.display))
                    .foregroundStyle(Puff.Palette.ink)

                VStack(spacing: 4) {
                    Text("\(card.age) 岁 · \(city) · \(compact ? card.occupation.components(separatedBy: "，").first ?? card.occupation : card.occupation)")
                        .font(.puff(.subheadline, Puff.Weight.emphasis))
                        .foregroundStyle(candy.deep)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(compact ? card.personality.components(separatedBy: "；").first ?? card.personality : card.personality)
                        .font(.puff(.footnote, Puff.Weight.body))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineLimit(compact ? 2 : 3)
                }

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(card.localizedHobbies.prefix(compact ? 2 : 3), id: \.self) { hobby in
                        PuffTag(hobby, candy: candy)
                    }
                }
            }
            .padding(.horizontal, compact ? 12 : Puff.Space.l)
            .padding(.bottom, compact ? 12 : Puff.Space.l)
        }
        .frame(maxHeight: 520)
        .puffCard(radius: Puff.Radius.huge)
    }
}
