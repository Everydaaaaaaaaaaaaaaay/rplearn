import DesignSystem
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore

    public init(rosterStore: RosterStore, economyStore: EconomyStore) {
        self.rosterStore = rosterStore
        self.economyStore = economyStore
    }
}

public struct RosterView: View {
    private let deps: RosterDependencies
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @State private var friends: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true

    public init(
        deps: RosterDependencies,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.deps = deps
        self.chatBuilder = chatBuilder
    }

    private var partners: [CharacterDTO] { friends.filter(\.isMainCharacter) }
    private var encounters: [CharacterDTO] { friends.filter { !$0.isMainCharacter } }
    private var slotLimit: Int { max(profile?.friendSlotLimit ?? 10, 1) }
    private var remainingSlots: Int { max(slotLimit - occupiedSlots, 0) }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                relationshipHero
                partnerSection
                encounterSection
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, 40)
        }
        .background(Color.dsBackground)
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.large)
        .task { await reload() }
        .refreshable { await reload() }
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(DSSpacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.card))
            }
        }
    }

    private var relationshipHero: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [.dsSkyDeep, .dsQuiz],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            relationshipConstellation
                .padding(.top, 4)
                .padding(.trailing, 2)

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("JOURNEY BONDS")
                        .font(.caption2.weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("旅途关系")
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    Text(heroDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProgressView(
                    value: Double(occupiedSlots),
                    total: Double(slotLimit)
                )
                .tint(.white)
                .background(.white.opacity(0.18), in: Capsule())

                HStack(spacing: DSSpacing.xs) {
                    heroStat(
                        value: "\(partners.count)",
                        title: "剧情旅伴",
                        icon: "star.fill"
                    )
                    heroStat(
                        value: "\(occupiedSlots)/\(slotLimit)",
                        title: "好友位",
                        icon: "person.2.fill"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.dsQuiz.opacity(0.16), radius: 18, y: 9)
        .accessibilityElement(children: .combine)
    }

    private var heroDetail: String {
        if occupiedSlots >= slotLimit {
            return "好友位已满，剧情旅伴仍然可以继续加入"
        }
        return "还可结识 \(remainingSlots) 位城市朋友，剧情旅伴不占好友位"
    }

    private var relationshipConstellation: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 160, height: 160)
                .offset(x: 45, y: -48)
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 82, weight: .black))
                .foregroundStyle(.white.opacity(0.085))
                .offset(x: 18, y: 10)
        }
    }

    private func heroStat(value: String, title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
            VStack(alignment: .leading, spacing: -1) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.black))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.14), in: Capsule())
    }

    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionHeader(
                eyebrow: "STORY COMPANIONS",
                title: "剧情旅伴",
                detail: "与你共同推进旅程的核心角色"
            )

            if partners.isEmpty {
                companionEmptyState
            } else {
                VStack(spacing: DSSpacing.sm) {
                    ForEach(partners) { character in
                        NavigationLink {
                            CharacterProfileView(character: character, chatBuilder: chatBuilder)
                        } label: {
                            partnerCard(character)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var encounterSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionHeader(
                eyebrow: "CITY ENCOUNTERS",
                title: "城市邂逅",
                detail: "\(encounters.count) 位在路上认识的朋友"
            )

            if encounters.isEmpty {
                encounterEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(encounters.enumerated()), id: \.element.id) { index, character in
                        NavigationLink {
                            CharacterProfileView(character: character, chatBuilder: chatBuilder)
                        } label: {
                            encounterRow(character)
                        }
                        .buttonStyle(.plain)

                        if index < encounters.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .dsSurface(.grouped, padding: 0)
            }
        }
    }

    private func sectionHeader(eyebrow: String, title: String, detail: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption2.weight(.black))
                    .tracking(1.15)
                    .foregroundStyle(Color.dsSkyDeep)
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func partnerCard(_ character: CharacterDTO) -> some View {
        let tint = characterTint(character.card.name)

        return ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [tint.opacity(0.16), Color.dsSurface],
                startPoint: .leading,
                endPoint: .trailing
            )

            Circle()
                .fill(tint.opacity(0.07))
                .frame(width: 116, height: 116)
                .offset(x: 36, y: 34)

            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.24), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    AvatarBadge(name: character.card.name, tint: tint, size: 62)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(tint)
                        Text("旅程核心角色")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Text(character.card.name)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(character.card.nationality) · \(character.card.occupation)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let hobby = character.card.localizedHobbies.first {
                        Label(hobby, systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(DSSpacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.08), radius: 10, y: 5)
    }

    private func encounterRow(_ character: CharacterDTO) -> some View {
        HStack(spacing: DSSpacing.sm) {
            AvatarBadge(
                name: character.card.name,
                tint: characterTint(character.card.name),
                size: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(character.card.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(character.card.nationality) · \(character.card.occupation)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !character.card.localizedHobbies.isEmpty {
                    Text(character.card.localizedHobbies.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(characterTint(character.card.name))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(alignment: .trailing, spacing: 5) {
                Text(character.metAt.formatted(.dateTime.month().day()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(DSSpacing.md)
    }

    private var companionEmptyState: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.dsSunset)
                .frame(width: 48, height: 48)
                .background(Color.dsSunset.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("旅伴尚未加入")
                    .font(.headline)
                Text("继续主线剧情，会遇见与你并肩旅行的伙伴")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private var encounterEmptyState: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.dsCyan)
                .frame(width: 48, height: 48)
                .background(Color.dsCyan.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("下一次邂逅还在路上")
                    .font(.headline)
                Text("去城市活动走走，也许会认识新的当地朋友")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private func characterTint(_ name: String) -> Color {
        let palette: [Color] = [.dsSky, .dsCyan, .dsSunset, .dsSuccess, .dsQuiz, .pink]
        let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[Int(value.magnitude % UInt(palette.count))]
    }

    private func reload() async {
        async let loadedFriends = try? deps.rosterStore.friends()
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()
        friends = await loadedFriends ?? []
        profile = await loadedProfile
        occupiedSlots = await loadedSlots ?? 0
        isLoading = false
    }
}

public struct CharacterProfileView: View {
    let character: CharacterDTO
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    public init(
        character: CharacterDTO,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.character = character
        self.chatBuilder = chatBuilder
    }

    private var card: CharacterCard { character.card }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileHero
                infoCard("性格", text: card.personality, icon: "sparkles")
                hobbiesCard
                infoCard("外貌", text: card.appearance, icon: "person.crop.rectangle")
                if let speechStyle = card.speechStyle {
                    infoCard("说话风格", text: speechStyle, icon: "quote.bubble")
                }
                if let background = card.background {
                    infoCard("背景故事", text: background, icon: "book.closed")
                }
                infoCard(
                    "相识于",
                    text: character.metAt.formatted(date: .abbreviated, time: .omitted),
                    icon: "mappin.and.ellipse"
                )
                NavigationLink {
                    chatBuilder(character)
                } label: {
                    Label("发消息", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.dsActionPrimary)
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileHero: some View {
        VStack(spacing: DSSpacing.sm) {
            AvatarBadge(name: card.name, size: 88)
            Text(card.name).font(.title2.bold())
            HStack(spacing: DSSpacing.xs) {
                DSChip("\(card.age) 岁", tint: .dsSky)
                DSChip(card.nationality, tint: .dsCyan)
                DSChip(card.occupation, tint: .dsSunset)
            }
        }
        .frame(maxWidth: .infinity)
        .dsSurface(.grouped)
    }

    private var hobbiesCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("爱好", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.dsSunset)
            FlowLayout(spacing: 6, lineSpacing: 7) {
                ForEach(card.localizedHobbies, id: \.self) { DSChip($0, tint: .dsSky) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private func infoCard(_ title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.dsSky)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsSurface(.grouped)
    }
}
