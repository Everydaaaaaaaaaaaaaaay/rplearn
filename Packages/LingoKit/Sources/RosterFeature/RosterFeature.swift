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
    @State private var favoriteErrorMessage: String?

    public init(
        deps: RosterDependencies,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.deps = deps
        self.chatBuilder = chatBuilder
    }

    private var favoriteContacts: [CharacterDTO] {
        sorted(friends.filter(\.isFavorite))
    }
    private var allContacts: [CharacterDTO] { sorted(friends) }
    private var slotLimit: Int { max(profile?.friendSlotLimit ?? 10, 1) }
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [CharacterDTO] {
        guard isSearching else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sorted(friends.filter { character in
            [
                character.card.name,
                character.card.nationality,
                character.card.occupation,
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        })
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
                        favoriteShortcuts
                        contactSection(
                            title: "联系人",
                            icon: "person.2",
                            tint: .dsSkyDeep,
                            people: allContacts,
                            emptyDescription: ""
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
        .alert(
            "无法更新特别关心",
            isPresented: Binding(
                get: { favoriteErrorMessage != nil },
                set: { if !$0 { favoriteErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "请稍后再试")
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

    private var favoriteShortcuts: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Label("特别关心", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(Color.dsSunset)
                Spacer()
                if !favoriteContacts.isEmpty {
                    Text("\(favoriteContacts.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if favoriteContacts.isEmpty {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "star")
                        .font(.title3)
                        .foregroundStyle(Color.dsSunset)
                        .frame(width: 42, height: 42)
                        .background(Color.dsSunset.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("还没有特别关心")
                            .font(.subheadline.weight(.medium))
                        Text("进入联系人详情，点击“特别关心”即可添加")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: DSSpacing.md) {
                        ForEach(favoriteContacts) { character in
                            favoriteLink(character)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(DSSpacing.md)
        .dsSceneGlass(radius: DSRadius.card, tint: Color.dsSunset.opacity(0.08))
    }

    private func favoriteLink(_ character: CharacterDTO) -> some View {
        NavigationLink {
            friendDestination(character)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarBadge(name: character.card.name, size: 54)
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.dsSunset, in: Circle())
                        .overlay { Circle().stroke(.white, lineWidth: 2) }
                }
                Text(character.card.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteMenuButton(for: character)
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
            friendDestination(character)
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

                if character.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsSunset)
                        .accessibilityLabel("特别关心")
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteMenuButton(for: character)
        }
    }

    private func friendDestination(_ character: CharacterDTO) -> some View {
        CharacterProfileView(
            character: character,
            rosterStore: deps.rosterStore,
            onFavoriteChanged: { isFavorite in
                applyFavoriteState(characterID: character.id, isFavorite: isFavorite)
            },
            chatBuilder: chatBuilder
        )
    }

    private func favoriteMenuButton(for character: CharacterDTO) -> some View {
        Button {
            updateFavorite(character, isFavorite: !character.isFavorite)
        } label: {
            Label(
                character.isFavorite ? "取消特别关心" : "设为特别关心",
                systemImage: character.isFavorite ? "star.slash" : "star"
            )
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
        .foregroundStyle(.white.opacity(0.86))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.bottom, DSSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
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

    private func sorted(_ contacts: [CharacterDTO]) -> [CharacterDTO] {
        contacts.sorted {
            $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending
        }
    }

    private func updateFavorite(_ character: CharacterDTO, isFavorite: Bool) {
        Task {
            do {
                try await deps.rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: isFavorite
                )
                applyFavoriteState(characterID: character.id, isFavorite: isFavorite)
            } catch {
                favoriteErrorMessage = "没有保存成功，请稍后再试。"
            }
        }
    }

    private func applyFavoriteState(characterID: UUID, isFavorite: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == characterID }) else { return }
        friends[index].isFavorite = isFavorite
    }
}

public struct CharacterProfileView: View {
    let character: CharacterDTO
    let rosterStore: RosterStore
    let onFavoriteChanged: @MainActor (Bool) -> Void
    let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @State private var isFavorite: Bool
    @State private var isUpdatingFavorite = false
    @State private var favoriteErrorMessage: String?

    public init(
        character: CharacterDTO,
        rosterStore: RosterStore,
        onFavoriteChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView
    ) {
        self.character = character
        self.rosterStore = rosterStore
        self.onFavoriteChanged = onFavoriteChanged
        self.chatBuilder = chatBuilder
        _isFavorite = State(initialValue: character.isFavorite)
    }

    private var card: CharacterCard { character.card }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileHero
                contactActions
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
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "无法更新特别关心",
            isPresented: Binding(
                get: { favoriteErrorMessage != nil },
                set: { if !$0 { favoriteErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "请稍后再试")
        }
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

    private var contactActions: some View {
        HStack(spacing: DSSpacing.sm) {
            NavigationLink {
                chatBuilder(character)
            } label: {
                Label("发消息", systemImage: "bubble.left.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsSky)

            Button {
                toggleFavorite()
            } label: {
                Group {
                    if isUpdatingFavorite {
                        ProgressView()
                    } else {
                        Label(
                            isFavorite ? "已特别关心" : "特别关心",
                            systemImage: isFavorite ? "star.fill" : "star"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? Color.dsSunset : Color.dsSkyDeep)
            .disabled(isUpdatingFavorite)
            .accessibilityValue(isFavorite ? "已开启" : "未开启")
        }
        .controlSize(.large)
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        isUpdatingFavorite = true
        Task {
            do {
                try await rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: newValue
                )
                isFavorite = newValue
                onFavoriteChanged(newValue)
            } catch {
                favoriteErrorMessage = "没有保存成功，请稍后再试。"
            }
            isUpdatingFavorite = false
        }
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
