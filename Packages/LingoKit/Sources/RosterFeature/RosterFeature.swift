import DesignSystem
import Foundation
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore
    public let regionName: @Sendable (String) -> String

    public init(
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    ) {
        self.rosterStore = rosterStore
        self.economyStore = economyStore
        self.regionName = regionName
    }
}

enum RosterPresentationPolicy {
    static func sorted(_ contacts: [CharacterDTO]) -> [CharacterDTO] {
        contacts.sorted {
            $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending
        }
    }

    static func filtered(
        _ contacts: [CharacterDTO],
        query: String,
        regionName: (String) -> String
    ) -> [CharacterDTO] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sorted(contacts) }
        return sorted(
            contacts.filter { character in
                [
                    character.card.name,
                    character.card.nationality,
                    character.card.occupation,
                    character.card.regionID,
                    regionName(character.card.regionID),
                ].contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            }
        )
    }

    static func favoriteContacts(
        in contacts: [CharacterDTO],
        isSearching: Bool
    ) -> [CharacterDTO] {
        guard !isSearching else { return [] }
        return sorted(contacts.filter(\.isFavorite))
    }

    static func friendGroupContacts(in contacts: [CharacterDTO]) -> [CharacterDTO] {
        sorted(contacts.filter { !$0.isFavorite })
    }

    static func isCapacityNearLimit(occupied: Int, limit: Int) -> Bool {
        guard limit > 0 else { return true }
        return Double(occupied) / Double(limit) >= 0.8
    }
}

public struct RosterView: View {
    private let deps: RosterDependencies
    private let reloadToken: Int
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var friends: [CharacterDTO] = []
    @State private var profile: UserProfileDTO?
    @State private var occupiedSlots = 0
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var favoriteSaveFailure: FavoriteSaveFailure?
    @AppStorage("lingotrip.roster.favorite-group-expanded")
    private var isFavoriteGroupExpanded = true
    @AppStorage("lingotrip.roster.friend-group-expanded")
    private var isFriendGroupExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var slotLimit: Int { max(profile?.friendSlotLimit ?? 10, 1) }
    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isSearching: Bool { !normalizedSearchText.isEmpty }
    private var isSearchActive: Bool { isSearchPresented || isSearching }
    private var allContacts: [CharacterDTO] {
        RosterPresentationPolicy.sorted(friends)
    }
    private var visibleContacts: [CharacterDTO] {
        RosterPresentationPolicy.filtered(
            friends,
            query: normalizedSearchText,
            regionName: deps.regionName
        )
    }
    private var favoriteContacts: [CharacterDTO] {
        RosterPresentationPolicy.favoriteContacts(in: friends, isSearching: isSearchActive)
    }
    private var friendContacts: [CharacterDTO] {
        RosterPresentationPolicy.friendGroupContacts(in: friends)
    }
    private var isCapacityNearLimit: Bool {
        RosterPresentationPolicy.isCapacityNearLimit(occupied: occupiedSlots, limit: slotLimit)
    }
    private var contactAvatarSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 58 : 48
    }
    public var body: some View {
        ZStack {
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .warm)
            navigationReadabilityWash
            sceneReadabilityWash
            directoryList
        }
        .navigationTitle("联系人")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "搜索姓名、职业或地区"
        )
        .dsCompactSearchToolbar()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: reloadToken) { await reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let failure = favoriteSaveFailure {
                saveErrorBanner(failure)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: favoriteSaveFailure?.id)
    }

    private var directoryList: some View {
        List {
            directoryContent
        }
        .listStyle(.plain)
        .listSectionSpacing(DSSpacing.xs)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var directoryContent: some View {
        if isLoading && friends.isEmpty {
            loadingRow
        } else if let loadErrorMessage, friends.isEmpty {
            loadErrorRow(loadErrorMessage)
        } else if isSearchActive {
            searchContent
        } else if friends.isEmpty {
            emptyState
        } else {
            if let loadErrorMessage {
                compactLoadErrorRow(loadErrorMessage)
            }
            if !favoriteContacts.isEmpty {
                favoriteContactsSection
            }
            friendsSection
        }
    }

    private var navigationReadabilityWash: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .black.opacity(0.1), location: 0.12),
                .init(color: .clear, location: 0.28),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var sceneReadabilityWash: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(
                    color: .black.opacity(contrast == .increased ? 0.16 : 0.06),
                    location: 0.24
                ),
                .init(
                    color: .black.opacity(contrast == .increased ? 0.34 : 0.16),
                    location: 0.58
                ),
                .init(
                    color: .black.opacity(contrast == .increased ? 0.48 : 0.24),
                    location: 1
                ),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var loadingRow: some View {
        HStack(spacing: DSSpacing.sm) {
            ProgressView()
            Text("正在载入联系人…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .listRowBackground(contactRowBackground)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private func loadErrorRow(_ message: String) -> some View {
        ContentUnavailableView {
            Label("无法载入联系人", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .listRowBackground(contactRowBackground)
        .listRowSeparator(.hidden)
    }

    private func compactLoadErrorRow(_ message: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label("刷新失败", systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
            Spacer(minLength: DSSpacing.xs)
            Button("重试") {
                Task { await reload() }
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Color.dsDanger)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("刷新联系人失败，\(message)，重试")
        .listRowBackground(Color.dsDanger.opacity(0.08))
    }

    @ViewBuilder
    private var searchContent: some View {
        if visibleContacts.isEmpty {
            ContentUnavailableView.search(text: normalizedSearchText)
                .frame(maxWidth: .infinity, minHeight: 360)
                .listRowBackground(contactRowBackground)
                .listRowSeparator(.hidden)
        } else {
            ForEach(visibleContacts) { character in
                contactLink(character)
            }
        }
    }

    private var favoriteContactsSection: some View {
        Section {
            if isFavoriteGroupExpanded {
                ForEach(favoriteContacts) { character in
                    contactLink(character)
                }
            }
        } header: {
            contactGroupHeader(
                title: "特别关心",
                count: favoriteContacts.count,
                systemImage: "star.fill",
                tint: .dsSunset,
                isExpanded: isFavoriteGroupExpanded,
                toggle: toggleFavoriteGroup
            )
        }
    }

    private var friendsSection: some View {
        Section {
            if isFriendGroupExpanded {
                ForEach(friendContacts) { character in
                    contactLink(character)
                }
            }
        } header: {
            contactGroupHeader(
                title: "好友",
                count: friendContacts.count,
                systemImage: "person.2.fill",
                tint: .dsSky,
                isExpanded: isFriendGroupExpanded,
                toggle: toggleFriendGroup
            )
        } footer: {
            if isFriendGroupExpanded {
                capacityFooter
            }
        }
    }

    private func contactGroupHeader(
        title: String,
        count: Int,
        systemImage: String,
        tint: Color,
        isExpanded: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 14)

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer(minLength: DSSpacing.sm)

                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .background(groupHeaderBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(count) 位联系人，\(isExpanded ? "已展开" : "已折叠")")
        .accessibilityHint(isExpanded ? "双击折叠分组" : "双击展开分组")
    }

    private func toggleFavoriteGroup() {
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            isFavoriteGroupExpanded.toggle()
        }
    }

    private func toggleFriendGroup() {
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            isFriendGroupExpanded.toggle()
        }
    }

    private var groupHeaderBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(contrast == .increased ? 0.42 : 0.2),
                Color.black.opacity(contrast == .increased ? 0.32 : 0.12),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var contactRowBackground: Color {
        Color.black.opacity(contrast == .increased ? 0.34 : 0.13)
    }

    private func contactLink(_ character: CharacterDTO) -> some View {
        let avatarSize = contactAvatarSize

        return NavigationLink {
            friendDestination(character)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                AvatarBadge(name: character.card.name, size: avatarSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(character.card.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                        if character.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.dsSunset)
                                .accessibilityHidden(true)
                        }
                    }

                    Text(friendStatus(character))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contactAccessibilityLabel(character))
            .accessibilityHint("打开联系人详情")
        }
        .listRowInsets(
            EdgeInsets(
                top: 8,
                leading: DSSpacing.md,
                bottom: 8,
                trailing: DSSpacing.md
            )
        )
        .listRowBackground(contactRowBackground)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + avatarSize + DSSpacing.sm
        }
        .contextMenu {
            favoriteMenuButton(for: character)
        }
    }

    private func friendDestination(_ character: CharacterDTO) -> some View {
        CharacterProfileView(
            character: character,
            regionName: deps.regionName(character.card.regionID),
            rosterStore: deps.rosterStore,
            onFavoriteChanged: { isFavorite in
                applyFavoriteState(characterID: character.id, isFavorite: isFavorite)
            },
            chatBuilder: chatBuilder,
            callBuilder: callBuilder
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
            return "剧情旅伴 · \(compactOccupation(character.card.occupation))"
        }
        return "\(deps.regionName(character.card.regionID)) · \(compactOccupation(character.card.occupation))"
    }

    private func compactOccupation(_ occupation: String) -> String {
        occupation.components(separatedBy: CharacterSet(charactersIn: "，,\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? occupation
    }

    private func contactAccessibilityLabel(_ character: CharacterDTO) -> String {
        var components = [character.card.name]
        components.append(
            character.isMainCharacter ? "剧情旅伴" : deps.regionName(character.card.regionID)
        )
        components.append(compactOccupation(character.card.occupation))
        if character.isFavorite {
            components.append("已特别关心")
        }
        return components.joined(separator: "，")
    }

    private var capacityFooter: some View {
        Label {
            Text("好友位 \(occupiedSlots)/\(slotLimit) · 剧情旅伴不占好友位")
                .monospacedDigit()
        } icon: {
            Image(systemName: isCapacityNearLimit ? "person.crop.circle.badge.exclamationmark" : "person.2")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .fontWeight(isCapacityNearLimit ? .semibold : .regular)
        .foregroundStyle(
            isCapacityNearLimit
                ? AnyShapeStyle(Color.dsWarning)
                : AnyShapeStyle(Color.white.opacity(0.68))
        )
        .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
        .accessibilityLabel(
            "好友位已使用 \(occupiedSlots) 个，共 \(slotLimit) 个。剧情旅伴不占好友位"
        )
        .listRowBackground(Color.black.opacity(contrast == .increased ? 0.3 : 0.09))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有联系人",
            systemImage: "person.2",
            description: Text("继续旅行，认识的新朋友会出现在这里")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
        .listRowBackground(contactRowBackground)
        .listRowSeparator(.hidden)
    }

    private func saveErrorBanner(_ failure: FavoriteSaveFailure) -> some View {
        SaveErrorBanner(
            message: "特别关心没有保存成功",
            retry: {
                guard let character = friends.first(where: { $0.id == failure.characterID }) else {
                    favoriteSaveFailure = nil
                    return
                }
                updateFavorite(character, isFavorite: failure.targetValue)
            },
            dismiss: { favoriteSaveFailure = nil }
        )
    }

    private func reload() async {
        if friends.isEmpty { isLoading = true }
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedSlots = try? deps.rosterStore.occupiedFriendSlots()

        do {
            friends = try await deps.rosterStore.friends()
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "请检查网络或稍后重试。"
        }

        profile = await loadedProfile
        occupiedSlots = await loadedSlots ?? occupiedSlots
        isLoading = false
    }

    private func updateFavorite(_ character: CharacterDTO, isFavorite: Bool) {
        let previousValue = character.isFavorite
        favoriteSaveFailure = nil
        applyFavoriteState(characterID: character.id, isFavorite: isFavorite, animated: true)

        Task {
            do {
                try await deps.rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: isFavorite
                )
                Haptics.selection()
            } catch {
                applyFavoriteState(
                    characterID: character.id,
                    isFavorite: previousValue,
                    animated: true
                )
                favoriteSaveFailure = FavoriteSaveFailure(
                    characterID: character.id,
                    targetValue: isFavorite
                )
            }
        }
    }

    private func applyFavoriteState(
        characterID: UUID,
        isFavorite: Bool,
        animated: Bool = false
    ) {
        guard let index = friends.firstIndex(where: { $0.id == characterID }) else { return }
        withAnimation(animated && !reduceMotion ? DSAnimation.snappy : nil) {
            friends[index].isFavorite = isFavorite
        }
    }
}

public struct CharacterProfileView: View {
    private let character: CharacterDTO
    private let regionName: String
    private let rosterStore: RosterStore
    private let onFavoriteChanged: @MainActor (Bool) -> Void
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var isFavorite: Bool
    @State private var isUpdatingFavorite = false
    @State private var failedFavoriteTarget: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        character: CharacterDTO,
        regionName: String,
        rosterStore: RosterStore,
        onFavoriteChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.character = character
        self.regionName = regionName
        self.rosterStore = rosterStore
        self.onFavoriteChanged = onFavoriteChanged
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let failedFavoriteTarget {
                SaveErrorBanner(
                    message: "特别关心没有保存成功",
                    retry: { setFavorite(failedFavoriteTarget) },
                    dismiss: { self.failedFavoriteTarget = nil }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: failedFavoriteTarget)
    }

    private var profileHero: some View {
        VStack(spacing: DSSpacing.sm) {
            AvatarBadge(name: card.name, size: 96)
            Text(card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(
                [
                    character.isMainCharacter ? "剧情旅伴" : "旅行朋友",
                    card.occupation,
                    regionName,
                ].joined(separator: " · ")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Text("\(card.nationality) · \(card.age) 岁")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .dsSurface(.grouped)
        .accessibilityElement(children: .combine)
    }

    private var contactActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(spacing: DSSpacing.sm))

        return layout {
            NavigationLink {
                chatBuilder(character)
            } label: {
                contactActionLabel("发消息", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsSky)

            if let callBuilder {
                NavigationLink {
                    callBuilder(character)
                } label: {
                    contactActionLabel("打电话", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
                .tint(Color.dsSkyDeep)
            }

            Button {
                setFavorite(!isFavorite)
            } label: {
                contactActionLabel(
                    isFavorite ? "已特别关心" : "特别关心",
                    systemImage: isFavorite ? "star.fill" : "star"
                )
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? Color.dsSunset : Color.dsSkyDeep)
            .disabled(isUpdatingFavorite)
            .accessibilityValue(isFavorite ? "已开启" : "未开启")
            .accessibilityHint(isFavorite ? "双击取消特别关心" : "双击设为特别关心")
        }
    }

    private func contactActionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
    }

    private func setFavorite(_ newValue: Bool) {
        guard !isUpdatingFavorite else { return }
        let previousValue = isFavorite
        failedFavoriteTarget = nil
        isUpdatingFavorite = true
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            isFavorite = newValue
        }
        onFavoriteChanged(newValue)

        Task {
            do {
                try await rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: newValue
                )
                Haptics.selection()
            } catch {
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    isFavorite = previousValue
                }
                onFavoriteChanged(previousValue)
                failedFavoriteTarget = newValue
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

private struct FavoriteSaveFailure: Identifiable {
    let id = UUID()
    let characterID: UUID
    let targetValue: Bool
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDanger)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("重试", action: retry)
                .font(.footnote.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.leading, DSSpacing.md)
        .padding(.trailing, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(.thickMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.dsBorder, lineWidth: 1) }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
