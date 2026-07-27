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
    @State private var arePartnersExpanded = true
    @State private var areEncountersExpanded = true

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
        List {
            if isSearching {
                searchSection
            } else if friends.isEmpty && !isLoading {
                emptyState
            } else {
                partnerSection
                encounterSection
                capacityNote
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.dsBackground)
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索好友"
        )
        .task { await reload() }
        .refreshable { await reload() }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private var partnerSection: some View {
        Section {
            groupHeader(
                title: "特别关心",
                count: partners.count,
                isExpanded: $arePartnersExpanded
            )

            if arePartnersExpanded {
                ForEach(partners) { character in
                    friendLink(character)
                }
            }
        }
    }

    private var encounterSection: some View {
        Section {
            groupHeader(
                title: "我的好友",
                count: encounters.count,
                isExpanded: $areEncountersExpanded
            )

            if areEncountersExpanded {
                ForEach(encounters) { character in
                    friendLink(character)
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(searchResults) { character in
                    friendLink(character)
                }
            } header: {
                Text("搜索结果")
                    .textCase(nil)
            }
        }
    }

    private func groupHeader(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .frame(width: 12)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(
            EdgeInsets(top: 0, leading: DSSpacing.md, bottom: 0, trailing: DSSpacing.md)
        )
        .listRowBackground(Color.dsSurface)
        .listRowSeparator(.hidden)
        .accessibilityLabel("\(title)，\(count) 位好友")
        .accessibilityValue(isExpanded.wrappedValue ? "已展开" : "已收起")
        .accessibilityHint(isExpanded.wrappedValue ? "轻点收起分组" : "轻点展开分组")
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
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(
            EdgeInsets(top: 5, leading: DSSpacing.md, bottom: 5, trailing: DSSpacing.md)
        )
        .listRowBackground(Color.dsSurface)
        .listRowSeparatorTint(Color.dsBorder.opacity(0.72))
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            DSSpacing.md + 46 + DSSpacing.sm
        }
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
        .listRowInsets(
            EdgeInsets(
                top: DSSpacing.sm,
                leading: DSSpacing.md,
                bottom: DSSpacing.lg,
                trailing: DSSpacing.md
            )
        )
        .listRowBackground(Color.dsBackground)
        .listRowSeparator(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有好友",
            systemImage: "person.2",
            description: Text("继续旅行，认识的伙伴会出现在这里")
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
