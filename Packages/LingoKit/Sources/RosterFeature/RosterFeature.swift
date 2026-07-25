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

    public var body: some View {
        List {
            slotSection
            characterSection("伙伴", characters: partners)
            characterSection("旅途中认识的朋友", characters: encounters)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("好友")
        .task { await reload() }
        .refreshable { await reload() }
        .overlay {
            if isLoading { ProgressView() }
        }
    }

    private var slotSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Label("好友位", systemImage: "person.2.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(occupiedSlots) / \(profile?.friendSlotLimit ?? 10)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(occupiedSlots),
                    total: Double(max(profile?.friendSlotLimit ?? 10, 1))
                )
                .tint(.dsSky)
                Text("城市伙伴不占好友位")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }

    @ViewBuilder
    private func characterSection(_ title: String, characters: [CharacterDTO]) -> some View {
        Section(title) {
            if characters.isEmpty {
                Text("还没有朋友，去城市活动逛逛吧")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(characters) { character in
                    NavigationLink {
                        CharacterProfileView(character: character, chatBuilder: chatBuilder)
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            AvatarBadge(name: character.card.name, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(character.card.name).font(.headline)
                                Text("\(character.card.nationality) · \(character.card.occupation)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
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
                .buttonStyle(.duoPrimary)
            }
            .padding(DSSpacing.md)
            .padding(.bottom, 90)
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
        .dsCard()
    }

    private var hobbiesCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("爱好", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.dsSunset)
            FlowLayout(spacing: 6, lineSpacing: 7) {
                ForEach(card.hobbies, id: \.self) { DSChip($0, tint: .dsSky) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
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
        .dsCard()
    }
}
