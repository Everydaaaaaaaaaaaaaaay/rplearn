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
    private enum ContactSection: Hashable, CaseIterable {
        case partners
        case friends
        case search
    }

    private let deps: RosterDependencies
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView

    @State private var friends: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var expandedSections = Set(ContactSection.allCases)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    private var scenePrimaryText: Color { .dsSceneTextPrimary }
    private var sceneSecondaryText: Color { .dsSceneTextSecondary }
    private var sceneTertiaryText: Color { .dsSceneTextTertiary }
    private var sceneGlassTint: Color { Color.dsBrandInk.opacity(0.04) }

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
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .cool)

            ScrollView {
                LazyVStack(spacing: DSSpacing.md) {
                    if isSearching {
                        searchSection
                    } else if friends.isEmpty && !isLoading {
                        emptyState
                    } else {
                        contactGroupsCard
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
                    .tint(scenePrimaryText)
                    .padding(DSSpacing.lg)
                    .dsSceneGlass(
                        radius: DSRadius.card,
                        tint: sceneGlassTint,
                        legibility: .shielded
                    )
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(DSSpacing.xl)
                .foregroundStyle(scenePrimaryText)
                .dsSceneGlass(
                    tint: sceneGlassTint,
                    legibility: .shielded
                )
        } else {
            contactSection(
                section: .search,
                title: "搜索结果",
                icon: "magnifyingglass",
                tint: .dsSkyDeep,
                people: searchResults
            )
            .dsSceneGlass(
                tint: sceneGlassTint,
                legibility: .shielded
            )
        }
    }

    private var contactGroupsCard: some View {
        VStack(spacing: 0) {
            contactSection(
                section: .partners,
                title: "特别关心",
                icon: "star.fill",
                tint: .dsSunset,
                people: partners
            )

            Divider()
                .overlay(scenePrimaryText.opacity(0.14))
                .padding(.horizontal, DSSpacing.md)

            contactSection(
                section: .friends,
                title: "朋友",
                icon: "person.2.fill",
                tint: .dsSkyDeep,
                people: encounters
            )
        }
        .dsSceneGlass(
            tint: sceneGlassTint,
            legibility: .shielded
        )
    }

    private func contactSection(
        section: ContactSection,
        title: String,
        icon: String,
        tint: Color,
        people: [CharacterDTO]
    ) -> some View {
        let isExpanded = expandedSections.contains(section)

        return VStack(spacing: 0) {
            sectionHeader(
                section: section,
                title: title,
                icon: icon,
                tint: tint,
                peopleCount: people.count,
                isExpanded: isExpanded
            )

            if isExpanded, !people.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(scenePrimaryText.opacity(0.1))
                        .padding(.leading, DSSpacing.md)

                    ForEach(Array(people.enumerated()), id: \.element.id) { index, character in
                        friendLink(character)
                        if index < people.count - 1 {
                            Divider()
                                .overlay(scenePrimaryText.opacity(0.08))
                                .padding(.leading, DSSpacing.md + 56 + DSSpacing.sm)
                        }
                    }
                }
                .transition(sectionTransition)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(
        section: ContactSection,
        title: String,
        icon: String,
        tint: Color,
        peopleCount: Int,
        isExpanded: Bool
    ) -> some View {
        if peopleCount > 0 {
            Button {
                toggle(section)
            } label: {
                sectionHeaderLabel(
                    section: section,
                    title: title,
                    icon: icon,
                    tint: tint,
                    peopleCount: peopleCount,
                    isExpanded: isExpanded,
                    showsDisclosure: true
                )
            }
            .buttonStyle(RosterSectionHeaderButtonStyle())
            .accessibilityLabel(
                sectionAccessibilityLabel(section, title: title, peopleCount: peopleCount)
            )
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            .accessibilityHint(isExpanded ? "双击折叠分组" : "双击展开分组")
        } else {
            sectionHeaderLabel(
                section: section,
                title: title,
                icon: icon,
                tint: tint,
                peopleCount: peopleCount,
                isExpanded: false,
                showsDisclosure: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                sectionAccessibilityLabel(section, title: title, peopleCount: peopleCount)
            )
        }
    }

    private func sectionHeaderLabel(
        section: ContactSection,
        title: String,
        icon: String,
        tint: Color,
        peopleCount: Int,
        isExpanded: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(scenePrimaryText)
                .lineLimit(1)

            if section == .friends {
                Text("好友位 \(occupiedSlots)/\(slotLimit)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(sceneSecondaryText)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            } else {
                Text("\(peopleCount)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(sceneSecondaryText)
            }

            Spacer(minLength: DSSpacing.xs)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(sceneTertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private func sectionAccessibilityLabel(
        _ section: ContactSection,
        title: String,
        peopleCount: Int
    ) -> String {
        guard section == .friends else {
            return "\(title)，\(peopleCount) 位联系人"
        }
        return "朋友，\(peopleCount) 位联系人。好友位已使用 \(occupiedSlots) 个，共 \(slotLimit) 个。剧情旅伴不占好友位"
    }

    private func toggle(_ section: ContactSection) {
        let animation: Animation? = reduceMotion
            ? nil
            : .spring(response: 0.34, dampingFraction: 1)
        withAnimation(animation) {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
    }

    private var sectionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private func friendLink(_ character: CharacterDTO) -> some View {
        NavigationLink {
            CharacterProfileView(character: character, chatBuilder: chatBuilder)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(name: character.card.name, size: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(character.card.name)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(scenePrimaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(friendStatus(character))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(sceneSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(RosterContactRowButtonStyle())
        .accessibilityLabel("\(character.card.name)，\(friendStatus(character))")
        .accessibilityHint("打开联系人详情")
    }

    private func friendStatus(_ character: CharacterDTO) -> String {
        if character.isMainCharacter {
            return "剧情旅伴 · \(character.card.occupation)"
        }
        return "\(character.card.nationality) · \(character.card.occupation)"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有好友",
            systemImage: "person.2",
            description: Text("继续旅行，认识的伙伴会出现在这里")
        )
        .padding(DSSpacing.xl)
        .foregroundStyle(scenePrimaryText)
        .dsSceneGlass(
            tint: sceneGlassTint,
            legibility: .shielded
        )
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

private struct RosterSectionHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct RosterContactRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.dsSceneTextPrimary.opacity(configuration.isPressed ? 0.06 : 0)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
