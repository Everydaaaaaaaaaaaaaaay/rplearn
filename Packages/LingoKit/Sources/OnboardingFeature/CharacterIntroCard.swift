import DesignSystem
import PersistenceKit
import SwiftUI

struct CharacterIntroCard: View {
    let character: CharacterDTO

    private static let regionNames = [
        "london": "伦敦",
        "melbourne": "墨尔本",
        "newyork": "纽约",
    ]
    private static let regionFlags = [
        "london": "🇬🇧",
        "melbourne": "🇦🇺",
        "newyork": "🇺🇸",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(
                    name: character.card.name,
                    size: 56,
                    imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:))
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(character.card.name)
                        .font(.headline)
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(character.card.localizedHobbies.prefix(3), id: \.self) {
                    DSChip($0, tint: DSScenePalette.city(character.card.regionID).accent)
                }
            }
            Text(character.card.personality)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .dsSurface(.floating, padding: DSSpacing.sm)
        .overlay(alignment: .topTrailing) {
            Text(Self.regionFlags[character.card.regionID] ?? "🌍")
                .font(.title3)
                .padding(8)
        }
    }

    private var metadata: String {
        let flag = Self.regionFlags[character.card.regionID] ?? "🌍"
        let region = Self.regionNames[character.card.regionID] ?? character.card.regionID
        return "\(flag) \(region) · \(character.card.age) 岁 · \(character.card.occupation)"
    }
}
