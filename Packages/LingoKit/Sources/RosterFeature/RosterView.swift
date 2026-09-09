import BackendKit
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI

/// 联系人 Tab：固定场景文字色与较厚的 shielded 玻璃。
///
/// 此处刻意不根据文字下方的单个背景像素切换深浅色，避免滚动时文字颜色闪烁，
/// 同时让联系人分组保持为一个稳定、可辨识的液态玻璃层。
public struct RosterView: View {
    private enum ContactSection: Hashable, CaseIterable {
        case favorites
        case friends
        case former
        case search
    }

    private let deps: RosterDependencies
    private let reloadToken: Int
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var friends: [CharacterDTO] = []
    @State private var formerContacts: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var travelerMatch: CharacterDTO?
    @State private var didFinishTravelerLookup = false
    @State private var expandedSections = Set(ContactSection.allCases)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: RosterDependencies,
        reloadToken: Int = 0,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
    }

    private var favoriteContacts: [CharacterDTO] {
        RosterPresentationPolicy.sorted(friends.filter(\.isFavorite))
    }

    private var otherContacts: [CharacterDTO] {
        RosterPresentationPolicy.sorted(friends.filter { !$0.isFavorite })
    }

    private var slotLimit: Int { max(profile?.friendSlotLimit ?? 3, 1) }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !normalizedSearchText.isEmpty }

    private var scenePrimaryText: Color { .dsSceneTextPrimary }
    private var sceneSecondaryText: Color { .dsSceneTextSecondary }
    private var sceneTertiaryText: Color { .dsSceneTextTertiary }
    private var sceneGlassTint: Color { Color.dsBrandInk.opacity(0.04) }

    private var sceneImageName: String {
        DSCitySceneAssets.imageName(
            for: .contacts,
            regionID: profile?.currentRegionID
        )
    }

    private var searchResults: [CharacterDTO] {
        guard isSearching else { return [] }
        var results = RosterPresentationPolicy.filtered(
            friends + formerContacts,
            query: normalizedSearchText,
            regionName: deps.regionName
        )
        if let travelerMatch, !results.contains(where: { $0.id == travelerMatch.id }) {
            results.insert(travelerMatch, at: 0)
        }
        return results
    }

    public var body: some View {
        searchAdaptedContent
            .navigationTitle("联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: reloadToken) { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { _ in
                Task {
                    friends = (try? await deps.rosterStore.friends()) ?? friends
                    formerContacts = (try? await deps.rosterStore.formerContacts()) ?? formerContacts
                }
            }
            .task(id: normalizedSearchText) { await lookupTravelerIDIfNeeded() }
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
    private var searchAdaptedContent: some View {
        if #available(iOS 26.0, *), DSPlatformVisualPolicy.usesLiquidGlass {
            sceneContent
                .dsSceneSearch(text: $searchText, title: "联系人", prompt: "搜索联系人")
        } else {
            sceneContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    DSLegacySceneSearchField(text: $searchText, prompt: "搜索联系人")
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.top, 4)
                        .padding(.bottom, DSSpacing.sm)
                }
        }
    }

    private var sceneContent: some View {
        ZStack {
            DSSceneBackdrop(imageName: sceneImageName, tone: .cool)

            ScrollView {
                LazyVStack(spacing: DSSpacing.md) {
                    if isSearching {
                        searchSection
                    } else if friends.isEmpty && formerContacts.isEmpty && !isLoading {
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
    }

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            ContentUnavailableView(
                isTravelerIDQuery && didFinishTravelerLookup ? "没有找到这个旅伴" : "没有找到联系人",
                systemImage: isTravelerIDQuery ? "number.circle" : "magnifyingglass",
                description: Text(
                    isTravelerIDQuery && didFinishTravelerLookup
                        ? "请检查旅伴号是否正确，或稍后在网络恢复后重试。"
                        : "试试姓名、备注、职业或旅伴号"
                )
            )
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
                section: .favorites,
                title: "特别关心",
                icon: "star.fill",
                tint: .dsSunset,
                people: favoriteContacts
            )

            Divider()
                .overlay(scenePrimaryText.opacity(0.14))
                .padding(.horizontal, DSSpacing.md)

            contactSection(
                section: .friends,
                title: "朋友",
                icon: "person.2.fill",
                tint: .dsSkyDeep,
                people: otherContacts
            )

            if !formerContacts.isEmpty {
                Divider()
                    .overlay(scenePrimaryText.opacity(0.14))
                    .padding(.horizontal, DSSpacing.md)

                contactSection(
                    section: .former,
                    title: "过往联系人",
                    icon: "clock.arrow.circlepath",
                    tint: .dsSceneTextSecondary,
                    people: RosterPresentationPolicy.sorted(formerContacts)
                )
            }
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
            CharacterProfileView(
                character: character,
                regionName: deps.regionName(character.card.regionID),
                rosterStore: deps.rosterStore,
                onFavoriteChanged: { isFavorite in
                    applyFavoriteState(characterID: character.id, isFavorite: isFavorite)
                },
                slotLimit: slotLimit,
                onContactRestored: { restored in
                    applyRestoredContact(restored)
                },
                chatBuilder: chatBuilder,
                callBuilder: callBuilder
            )
        } label: {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(
                    name: character.displayName,
                    size: 56,
                    imageName: character.card.avatarAssetName,
                    remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                    usesPendingPlaceholder: true
                )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(character.displayName)
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
        if character.contactStatus == .removed {
            return "过往联系人 · 可重新添加"
        }
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
        if friends.isEmpty { isLoading = true }
        async let loadedFriends = try? deps.rosterStore.friends()
        async let loadedFormerContacts = try? deps.rosterStore.formerContacts()
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()
        friends = await loadedFriends ?? friends
        formerContacts = await loadedFormerContacts ?? formerContacts
        profile = await loadedProfile ?? profile
        occupiedSlots = await loadedSlots ?? occupiedSlots
        isLoading = false
        await registerPendingPublicNPCs()
    }

    private func registerPendingPublicNPCs() async {
        guard let registry = deps.npcRegistry,
              let characters = try? await deps.rosterStore.allCharacters()
        else { return }
        guard !characters.isEmpty else { return }
        let coordinator = PublicNPCAvatarCoordinator(registry: registry, roster: deps.rosterStore)
        guard await coordinator.synchronize() > 0 else { return }
        friends = (try? await deps.rosterStore.friends()) ?? friends
        formerContacts = (try? await deps.rosterStore.formerContacts()) ?? formerContacts
    }

    private func applyFavoriteState(characterID: UUID, isFavorite: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == characterID }) else { return }
        friends[index].isFavorite = isFavorite
    }

    private var isTravelerIDQuery: Bool {
        let digits = normalizedSearchText.filter(\.isNumber)
        return digits.count == 11 && normalizedSearchText.allSatisfy { $0.isNumber || $0.isWhitespace }
    }

    @MainActor
    private func lookupTravelerIDIfNeeded() async {
        travelerMatch = nil
        didFinishTravelerLookup = false
        guard isTravelerIDQuery else { return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        let travelerID = normalizedSearchText.filter(\.isNumber)
        if let match = try? await deps.rosterStore.character(travelerID: travelerID) {
            // 尚未在剧情中相遇的主角不能被搜索提前剧透；已偶遇的随机 NPC 可以按号码找回。
            travelerMatch = match.isMainCharacter && match.contactStatus == .candidate ? nil : match
            didFinishTravelerLookup = true
            return
        }
        if let registry = deps.npcRegistry,
           let publicNPC = try? await registry.findPublicNPC(
               travelerID: travelerID
           ) {
            let level = profile?.difficultyLevel ?? .junior3
            if let localID = try? await deps.rosterStore.addCharacter(
                characterID: publicNPC.id,
                travelerID: publicNPC.travelerId,
                card: PublicNPCAdapter.characterCard(from: publicNPC),
                difficulty: level,
                isFriend: false
            ) {
                travelerMatch = try? await deps.rosterStore.character(id: localID)
                try? await registry.linkPublicNPC(
                    npcID: publicNPC.id,
                    localCharacterID: localID,
                    status: .candidate
                )
            }
        }
        didFinishTravelerLookup = true
    }

    private func applyRestoredContact(_ restored: CharacterDTO) {
        formerContacts.removeAll { $0.id == restored.id }
        if let index = friends.firstIndex(where: { $0.id == restored.id }) {
            friends[index] = restored
        } else {
            friends.append(restored)
        }
        if !restored.isMainCharacter { occupiedSlots += 1 }
        Task {
            try? await deps.npcRegistry?.linkPublicNPC(
                npcID: restored.id,
                localCharacterID: restored.id,
                status: .friend
            )
        }
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
