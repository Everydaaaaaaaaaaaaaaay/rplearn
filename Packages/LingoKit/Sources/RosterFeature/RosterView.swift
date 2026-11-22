import BackendKit
import DesignSystem
import DomainKit
import Foundation
import PersistenceKit
import SwiftUI

/// 联系人页：白色主基调，顶部是城市卡通明信片与好友位，
/// 下面是可折叠的“特别关心 / 朋友 / 过往联系人”厚卡片分组。
public struct RosterView: View {
    private enum ContactSection: Hashable, CaseIterable {
        case favorites
        case friends
        case former
        case search
    }

    private let deps: RosterDependencies
    private let reloadToken: Int
    private let resetToken: Int
    private struct LoadKey: Hashable {
        let token: Int
        let visible: Bool
    }
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var lastReplies: [UUID: Date] = [:]
    @State private var pendingPlans: [UUID: NPCReplyPlan] = [:]
    @State private var isVisible = false
    @State private var hasEntered = false
    @State private var friends: [CharacterDTO] = []
    @State private var formerContacts: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var travelerMatch: CharacterDTO?
    @State private var didFinishTravelerLookup = false
    @State private var expandedSections = Set(ContactSection.allCases)
    @State private var selectedContact: CharacterDTO?
    @Namespace private var profileZoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: RosterDependencies,
        reloadToken: Int = 0,
        resetToken: Int = 0,
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.resetToken = resetToken
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

    private var motion: Animation {
        Puff.Motion.resolve(Puff.Motion.bouncy, reduceMotion: reduceMotion)
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
        pageContent
            .puffPageHeader(
                title: "联系人",
                searchText: $searchText,
                searchPrompt: "搜索联系人",
                resetToken: resetToken
            )
            .navigationTitle("联系人")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { selectedContact != nil },
                set: { if !$0 { selectedContact = nil } }
            )) {
                if let selectedContact { contactDestination(selectedContact) }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: LoadKey(token: reloadToken, visible: isVisible)) {
                if isVisible { await reload() }
            }
            .onChange(of: resetToken) {
                selectedContact = nil
                searchText = ""
                expandedSections = Set(ContactSection.allCases)
                travelerMatch = nil
                didFinishTravelerLookup = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .rosterContactDidChange)) { _ in
                guard isVisible else { return }
                Task { await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { note in
                guard isVisible else { return }
                Task { await reloadPresence(characterID: note.object as? UUID) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .npcAvatarDidChange)) { note in
                guard isVisible, let characterID = note.object as? UUID else { return }
                Task { await refreshCharacter(characterID) }
            }
            .task(id: normalizedSearchText) { await lookupTravelerIDIfNeeded() }
    }

    private var pageContent: some View {
        ZStack {
            Puff.Palette.page.ignoresSafeArea()

            if isLoading && friends.isEmpty && formerContacts.isEmpty {
                PuffLoadingDots()
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Puff.Space.m) {
                        if isSearching {
                            searchSection
                                .transition(.puffDrop)
                        } else if friends.isEmpty && formerContacts.isEmpty {
                            emptyState
                                .puffEntrance(index: 0, isShown: hasEntered)
                        } else {
                            heroCard
                                .puffEntrance(index: 0, isShown: hasEntered)
                                .transition(.puffDrop)
                            contactSection(
                                section: .favorites,
                                title: "特别关心",
                                icon: "star.fill",
                                candy: .sunny,
                                people: favoriteContacts
                            )
                            .puffEntrance(index: 1, isShown: hasEntered)
                            contactSection(
                                section: .friends,
                                title: "朋友",
                                icon: "person.2.fill",
                                candy: .sky,
                                people: otherContacts
                            )
                            .puffEntrance(index: 2, isShown: hasEntered)
                            if !formerContacts.isEmpty {
                                contactSection(
                                    section: .former,
                                    title: "过往联系人",
                                    icon: "clock.arrow.circlepath",
                                    candy: .grape,
                                    people: RosterPresentationPolicy.sorted(formerContacts)
                                )
                                .puffEntrance(index: 3, isShown: hasEntered)
                            }
                        }
                    }
                    .padding(.horizontal, Puff.Space.m)
                    .padding(.top, 2)
                    .padding(.bottom, Puff.Space.xl)
                    .animation(motion, value: isSearching)
                }
                .refreshable { await reload() }
            }
        }
    }

    // MARK: - 明信片与好友位

    private var heroCard: some View {
        PuffSceneCard(
            regionID: profile?.currentRegionID,
            viewport: .east,
            sceneHeight: 140,
            isActive: isVisible,
            tapBurst: true
        ) {
            HStack(alignment: .center, spacing: Puff.Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    PuffTag(
                        PuffCity.nameZh(for: profile?.currentRegionID),
                        systemImage: "location.fill",
                        candy: .grape
                    )
                    Text("\(friends.count) 位旅伴")
                        .font(.puff(.title2, Puff.Weight.display))
                        .foregroundStyle(Puff.Palette.ink)
                        .contentTransition(.numericText(value: Double(friends.count)))
                }
                Spacer(minLength: 0)
                slotMeter
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(friends.count) 位旅伴。好友位已使用 \(occupiedSlots) 个，共 \(slotLimit) 个")
    }

    /// 好友位：名额少时一颗颗圆点，多时是一根进度条。
    private var slotMeter: some View {
        let nearLimit = RosterPresentationPolicy.isCapacityNearLimit(occupied: occupiedSlots, limit: slotLimit)
        let candy: PuffCandy = nearLimit ? .tangerine : .sky
        return VStack(alignment: .trailing, spacing: 6) {
            Text("好友位")
                .font(.puff(.caption, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.inkSoft)
            if slotLimit <= 6 {
                HStack(spacing: 5) {
                    ForEach(0..<slotLimit, id: \.self) { index in
                        let filled = index < occupiedSlots
                        Circle()
                            .fill(filled ? candy.base : Puff.Palette.cloud)
                            .overlay {
                                Circle().strokeBorder(filled ? candy.lip : Puff.Palette.line, lineWidth: 1.5)
                            }
                            .frame(width: 15, height: 15)
                            .scaleEffect(filled ? 1 : 0.86)
                            .animation(Puff.Motion.resolve(Puff.Motion.pop.delay(Double(index) * 0.05), reduceMotion: reduceMotion), value: filled)
                    }
                }
            } else {
                Capsule()
                    .fill(Puff.Palette.cloud)
                    .frame(width: 84, height: 12)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(candy.base)
                            .frame(width: 84 * min(CGFloat(occupiedSlots) / CGFloat(slotLimit), 1))
                    }
                    .animation(motion, value: occupiedSlots)
            }
            Text("\(occupiedSlots)/\(slotLimit)")
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .monospacedDigit()
                .foregroundStyle(candy.deep)
                .contentTransition(.numericText(value: Double(occupiedSlots)))
        }
    }

    // MARK: - 分组

    @ViewBuilder
    private var searchSection: some View {
        if searchResults.isEmpty {
            PuffEmptyState(
                isTravelerIDQuery && didFinishTravelerLookup ? "没有找到这个旅伴" : "没有找到联系人",
                bird: .gaga,
                pose: .curious
            )
            .frame(maxWidth: .infinity)
            .padding(.top, Puff.Space.l)
        } else {
            contactSection(
                section: .search,
                title: "搜索结果",
                icon: "magnifyingglass",
                candy: .sky,
                people: searchResults
            )
        }
    }

    private func contactSection(
        section: ContactSection,
        title: String,
        icon: String,
        candy: PuffCandy,
        people: [CharacterDTO]
    ) -> some View {
        let isExpanded = expandedSections.contains(section) || section == .search

        return VStack(spacing: 0) {
            sectionHeader(
                section: section,
                title: title,
                icon: icon,
                candy: candy,
                peopleCount: people.count,
                isExpanded: isExpanded
            )

            if isExpanded, !people.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, character in
                        friendLink(character)
                        if index < people.count - 1 {
                            Rectangle()
                                .fill(Puff.Palette.line)
                                .frame(height: 1)
                                .padding(.leading, Puff.Space.m + 52 + Puff.Space.s)
                                .padding(.trailing, Puff.Space.m)
                        }
                    }
                }
                .padding(.bottom, Puff.Space.xs)
                .transition(.puffDrop)
            }
        }
        .padding(.vertical, people.isEmpty ? 4 : 0)
        .padding(.top, people.isEmpty ? 0 : 4)
        .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge, style: .continuous))
        .puffCard(radius: Puff.Radius.huge)
    }

    @ViewBuilder
    private func sectionHeader(
        section: ContactSection,
        title: String,
        icon: String,
        candy: PuffCandy,
        peopleCount: Int,
        isExpanded: Bool
    ) -> some View {
        if peopleCount > 0, section != .search {
            Button {
                toggle(section)
            } label: {
                sectionHeaderLabel(
                    section: section, title: title, icon: icon, candy: candy,
                    peopleCount: peopleCount, isExpanded: isExpanded, showsDisclosure: true
                )
            }
            .buttonStyle(.puffRow)
            .accessibilityLabel(sectionAccessibilityLabel(section, title: title, peopleCount: peopleCount))
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            .accessibilityHint(isExpanded ? "双击折叠分组" : "双击展开分组")
        } else {
            sectionHeaderLabel(
                section: section, title: title, icon: icon, candy: candy,
                peopleCount: peopleCount, isExpanded: false, showsDisclosure: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sectionAccessibilityLabel(section, title: title, peopleCount: peopleCount))
        }
    }

    private func sectionHeaderLabel(
        section: ContactSection,
        title: String,
        icon: String,
        candy: PuffCandy,
        peopleCount: Int,
        isExpanded: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: Puff.Space.s) {
            PuffIconBubble(icon, candy: candy)
                .symbolEffect(.bounce, value: isExpanded)

            Text(title)
                .font(.puff(.title3, Puff.Weight.title))
                .foregroundStyle(Puff.Palette.ink)
                .lineLimit(1)

            Text("\(peopleCount)")
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .monospacedDigit()
                .foregroundStyle(candy.deep)
                .contentTransition(.numericText(value: Double(peopleCount)))
                .padding(.horizontal, 9)
                .frame(minWidth: 28, minHeight: 24)
                .background(candy.wash, in: Capsule())

            Spacer(minLength: Puff.Space.xs)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: Puff.Weight.icon, design: .rounded))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .frame(width: 30, height: 30)
                    .background(Puff.Palette.cloud, in: Circle())
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .padding(.horizontal, Puff.Space.m)
        .frame(minHeight: 60)
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
        Haptics.selection()
        withAnimation(motion) {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
    }

    private func friendLink(_ character: CharacterDTO) -> some View {
        Button {
            selectedContact = character
        } label: {
            RosterContactRowLabel(
                character: character,
                lastAssistantMessageAt: lastReplies[character.id],
                pendingReplyPlan: pendingPlans[character.id]
            )
        }
        .buttonStyle(.puffRow)
        .puffZoomSource(id: character.id, in: profileZoom, cornerRadius: Puff.Radius.medium)
        .accessibilityHint("打开联系人详情")
    }

    private func contactDestination(_ character: CharacterDTO) -> some View {
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
        .navigationTransition(.zoom(sourceID: character.id, in: profileZoom))
    }

    private var emptyState: some View {
        PuffEmptyState("还没有好友", pose: .wave)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private func reload() async {
        if friends.isEmpty { isLoading = true }
        defer { startEntranceIfNeeded() }
        async let loadedFriends = try? deps.rosterStore.friends()
        async let loadedFormerContacts = try? deps.rosterStore.formerContacts()
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()
        let nextFriends = await loadedFriends ?? friends
        let nextFormer = await loadedFormerContacts ?? formerContacts
        let nextProfile = await loadedProfile ?? profile
        let nextSlots = await loadedSlots ?? occupiedSlots
        withAnimation(hasEntered ? motion : nil) {
            if friends != nextFriends { friends = nextFriends }
            if formerContacts != nextFormer { formerContacts = nextFormer }
            if profile != nextProfile { profile = nextProfile }
            occupiedSlots = nextSlots
            isLoading = false
        }
        await reloadPresence()
        await registerPendingPublicNPCs()
    }

    private func reloadPresence(characterID: UUID? = nil) async {
        guard let store = deps.chatStore,
              let summaries = try? await store.conversationSummaries() else { return }
        var replies: [UUID: Date] = [:]
        var plans: [UUID: NPCReplyPlan] = [:]
        let characters = Dictionary((friends + formerContacts).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for summary in summaries where characterID == nil || summary.characterID == characterID {
            replies[summary.characterID] = summary.assistantMessageDates.last
            if summary.lastMessageRole == .user,
               let character = characters[summary.characterID],
               let history = try? await store.messages(conversationID: summary.conversationID),
               let user = history.last, user.role == .user, !user.isInterrupted {
                plans[character.id] = NPCAttentionPolicy.standard.replyPlan(
                    for: character, userMessage: user, history: history)
            }
        }
        if let characterID {
            if lastReplies[characterID] != replies[characterID] { lastReplies[characterID] = replies[characterID] }
            if pendingPlans[characterID] != plans[characterID] { pendingPlans[characterID] = plans[characterID] }
        } else {
            if lastReplies != replies { lastReplies = replies }
            if pendingPlans != plans { pendingPlans = plans }
        }
    }

    private func refreshCharacter(_ id: UUID) async {
        guard let character = try? await deps.rosterStore.character(id: id), isVisible else { return }
        if let index = friends.firstIndex(where: { $0.id == id }), friends[index] != character {
            friends[index] = character
        }
        if let index = formerContacts.firstIndex(where: { $0.id == id }), formerContacts[index] != character {
            formerContacts[index] = character
        }
        if travelerMatch?.id == id, travelerMatch != character { travelerMatch = character }
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
        withAnimation(motion) {
            friends[index].isFavorite = isFavorite
        }
    }

    /// 先以隐藏状态渲染首屏，再在下一帧触发逐块弹入。
    private func startEntranceIfNeeded() {
        guard !hasEntered else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            hasEntered = true
        }
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
