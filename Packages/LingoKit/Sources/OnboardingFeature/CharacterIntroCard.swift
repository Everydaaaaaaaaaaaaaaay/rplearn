import DesignSystem
import PersistenceKit
import SwiftUI

/// A concise introduction, with full details reserved for the later selection screen.
struct CharacterIntroCard: View {
    let character: CharacterDTO

    private var introduction: (city: String, occupation: String, detail: String) {
        switch character.card.regionID {
        case "london": ("伦敦", "旧书店店员 · 小说写作者", "嘴上爱损人，关心却藏在递给你的那本书里。")
        case "melbourne": ("墨尔本", "咖啡师 · 海洋生物学学生", "想到就去做；聊起海洋，眼睛会亮起来。")
        case "newyork": ("纽约", "街头摄影师", "走得快、聊得热闹，也留意同行的人有没有跟上。")
        default: (character.card.regionID, character.card.occupation, character.card.personality)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                AvatarBadge(name: character.card.name, size: 46,
                            imageName: character.card.avatarAssetName,
                            remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.card.name).font(.headline)
                    Text("\(introduction.city) · \(character.card.age) 岁")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                Text(introduction.occupation).font(.subheadline.weight(.medium))
                Text(introduction.detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.intro.\(character.card.regionID)")
    }
}
