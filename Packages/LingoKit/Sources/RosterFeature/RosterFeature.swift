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
    @State private var searchText = ""
    @State private var isSearchPresented = false

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
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [CharacterDTO] {
        guard isSearching else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return friends.filter { character in
            [
                character.card.name,
                character.card.nationality,
                character.card.occupation,
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var body: some View {
        ZStack {
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .warm)

            ScrollView {
                LazyVStack(spacing: DSSpacing.md) {
                    if isSearching {
                        searchSection
                    } else if friends.isEmpty && !isLoading {
                        emptyState
                    } else {
                        contactSection(
                            title: "特别关心",
                            icon: "star.fill",
                            tint: .dsSunset,
                            people: partners,
                            emptyDescription: "剧情旅伴会显示在这里"
                        )
                        contactSection(
                            title: "朋友",
                            icon: "person.2.fill",
                            tint: .dsSkyDeep,
                            people: encounters,
                            emptyDescription: "旅行中认识的新朋友会显示在这里"
                        )
                        capacityNote
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }
            .refreshable { await reload() }
        }
        .navigationTitle("联系人")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "搜索联系人"
        )
        .dsCompactSearchToolbar()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await reload() }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding(DSSpacing.lg)
                    .dsSceneGlass(radius: DSRadius.card, tint: Color.white.opacity(0.12))
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(DSSpacing.xl)
                .dsSceneGlass(tint: Color.white.opacity(0.12))
        } else {
            contactSection(
                title: "搜索结果",
                icon: "magnifyingglass",
                tint: .dsSkyDeep,
                people: searchResults,
                emptyDescription: ""
            )
        }
    }

    private func contactSection(
        title: String,
        icon: String,
        tint: Color,
        people: [CharacterDTO],
        emptyDescription: String
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(people.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(minHeight: 48)

            Divider()
                .padding(.leading, DSSpacing.md)

            if people.isEmpty {
                Text(emptyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.md)
            } else {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, character in
                    friendLink(character)
                    if index < people.count - 1 {
                        Divider()
                            .padding(.leading, DSSpacing.md + 46 + DSSpacing.sm)
                    }
                }
            }
        }
        .dsSceneGlass(tint: tint.opacity(0.08))
    }

    private func friendLink(_ character: CharacterDTO) -> some View {
        NavigationLink {
            CharacterProfileView(character: character, chatBuilder: chatBuilder)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(name: character.card.name, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(character.card.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(friendStatus(character))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DSSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func friendStatus(_ character: CharacterDTO) -> String {
        if character.isMainCharacter {
            return "剧情旅伴 · \(character.card.occupation)"
        }
        return "\(character.card.nationality) · \(character.card.occupation)"
    }

    private var capacityNote: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "person.2")
            Text("好友位 \(occupiedSlots)/\(slotLimit)")
                .monospacedDigit()
            Text("·")
            Text("剧情旅伴不占好友位")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .dsSceneGlass(radius: DSRadius.card, tint: Color.white.opacity(0.1))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有好友",
            systemImage: "person.2",
            description: Text("继续旅行，认识的伙伴会出现在这里")
        )
        .padding(DSSpacing.xl)
        .dsSceneGlass(tint: Color.white.opacity(0.12))
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
